# Dials a single senior for a single reminder occurrence via Telnyx. The actual
# interaction (speak, gather, hangup) is driven by Telnyx webhooks; this job only
# initiates the call and records the attempt.
class VoiceReminderJob < ApplicationJob
  queue_as :default

  # Calls are retried on transient Telnyx/HTTP failures. Telnyx's idempotency
  # means a retry with the same occurrence will not create duplicate calls.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(occurrence_id)
    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence
    return unless occurrence.status_pending?

    senior = occurrence.reminder.user

    # Checked here as well as in the scheduler. The scheduler check exists to
    # avoid enqueuing work that cannot run; this one exists because it is the
    # last thing between a person and a ringing telephone, and this job can be
    # reached without the scheduler -- a console, a retry hours after the
    # failure that caused it, some future caller that does not exist yet. A
    # call placed outside legal hours cannot be taken back, so the guard sits
    # at the choke point rather than only at the gate.
    unless senior.within_calling_hours?
      Rails.logger.info(
        "Voice reminder for occurrence #{occurrence.id} suppressed: " \
        "#{local_time_for(senior)} is outside " \
        "#{User::CALLING_HOURS.first}:00-#{User::CALLING_HOURS.last + 1}:00 for user #{senior.id}"
      )
      return
    end

    TelnyxVoiceService.dial(occurrence)
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
