# Dials a single senior for a single reminder occurrence via Telnyx. The actual
# interaction (speak, gather, hangup) is driven by Telnyx webhooks; this job only
# initiates the call and records the attempt.
class VoiceReminderJob < ApplicationJob
  queue_as :default

  # Calls are retried on transient Telnyx/HTTP failures. Telnyx's idempotency
  # means a retry with the same occurrence will not create duplicate calls.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(occurrence_id)
    # Checked here as well as in the scheduler, for the same reason the
    # calling-hours guard is: this job is reachable from a console, from a
    # retry, or from anything written later. A flag that only guards the gate
    # is not a kill switch.
    return unless FeatureFlag.enabled?(:phone_call_reminders)

    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence

    senior = occurrence.reminder.user

    # The scheduler's WHERE clause is a filter, not a guarantee. This job can run
    # long after it was enqueued, and is reachable directly — so a senior who
    # opted out in between, or who never opted in at all, must not be dialled on
    # the strength of a query that ran earlier.
    unless senior.voice_reminders_enabled? && senior.phone.present?
      Rails.logger.info "Voice reminder for occurrence #{occurrence.id} skipped: user #{senior.id} is not opted in to phone reminders"
      return
    end

    # Checked after the opt-in above, deliberately. Recording an undelivered
    # call for a senior who does not take phone calls would tell their caregiver
    # that Remindly failed to ring someone who never asked to be rung.
    #
    # Solid Queue can hold this job past the missed sweep's 60-minute grace, and
    # the sweep then closes the occurrence before any call is placed. Without a
    # record of that, the caregiver email falls back to saying the senior did not
    # mark it done — for a call still sitting in a queue. Recorded only when it
    # was swept to missed and nothing was ever attempted: an occurrence she
    # acknowledged herself is resolved, not undelivered.
    unless occurrence.status_pending?
      if occurrence.status_missed? && occurrence.telnyx_calls.empty?
        occurrence.suppress_call!(:not_attempted_in_time)
      end

      return
    end

    # Checked here as well as in the scheduler. The scheduler check exists to
    # avoid enqueuing work that cannot run; this one exists because it is the
    # last thing between a person and a ringing telephone, and this job can be
    # reached without the scheduler -- a console, a retry hours after the
    # failure that caused it, some future caller that does not exist yet. A
    # call placed outside legal hours cannot be taken back, so the guard sits
    # at the choke point rather than only at the gate.
    unless senior.within_calling_hours?
      # Record the refusal, do not leave it to be re-derived. The caregiver
      # email needs to know a call was withheld, and by the time it is sent the
      # only evidence would be scheduled_at — which answers for the schedule,
      # not for the moment the decision was actually taken.
      occurrence.suppress_call!(:outside_calling_hours)

      Rails.logger.info(
        "Voice reminder for occurrence #{occurrence.id} suppressed: " \
        "#{local_time_for(senior)} is outside " \
        "#{User::CALLING_HOURS.first}:00-#{User::CALLING_HOURS.max + 1}:00 for user #{senior.id}"
      )
      return
    end

    # Claim the attempt before dialling. This is the only thing standing between
    # a senior and a second call for the same dose when two scheduler runs, or a
    # redelivered job, reach here at once -- and it is also what bounds retries,
    # since a claim is refused once the cap is reached.
    attempt = TelnyxCall.reserve(occurrence, senior)

    if attempt.nil?
      Rails.logger.info(
        "Voice reminder for occurrence #{occurrence.id} not attempted: " \
        "cap of #{TelnyxCall::MAX_ATTEMPTS} reached, the last attempt is newer " \
        "than #{TelnyxCall::RETRY_AFTER.inspect}, or another run claimed it"
      )
      return
    end

    # Read the status again, after the claim and before the provider call. The
    # unique index only arbitrates between competing callers; it says nothing
    # about the occurrence being resolved meanwhile through the web page or a
    # keypress on an earlier attempt. Without this, a senior who has just marked
    # the dose done gets telephoned about it anyway.
    unless occurrence.reload.status_pending?
      # One transaction, because these two writes have to be true together. If
      # the process exits between them the row is cancelled with no reason
      # recorded, and nothing can repair it afterwards: the earlier status guard
      # refuses to record one because an attempt row now exists, and
      # phone_failure_reason ignores cancelled rows — so the caregiver would be
      # told the senior had not marked it done.
      ActiveRecord::Base.transaction do
        attempt.release_slot!(status: "cancelled", outcome: "no_response", completed_at: Time.current)

        # Only when the sweep closed it. One she resolved herself is a
        # resolution, not an undelivered call.
        occurrence.suppress_call!(:not_attempted_in_time) if occurrence.status_missed?
      end

      Rails.logger.info "Voice reminder for occurrence #{occurrence.id} cancelled: resolved while the attempt was being claimed"
      return
    end

    TelnyxVoiceService.dial(occurrence, attempt: attempt)
  end

  private

  # An unresolvable zone is one of the two reasons this guard fires, so the line
  # explaining the suppression must not itself depend on the zone resolving.
  # in_time_zone raises ArgumentError on a bad identifier, which -- under this
  # job's retry_on StandardError -- would turn a correctly suppressed call into
  # five retried failures.
  def local_time_for(senior)
    zone = ActiveSupport::TimeZone[senior.tz.to_s]
    return "an unresolvable timezone (#{senior.tz.inspect})" if zone.nil?

    Time.current.in_time_zone(zone).strftime("%H:%M %Z")
  end
end
