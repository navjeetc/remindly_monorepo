# frozen_string_literal: true

# Rings the caregiver at one position in a care receiver's escalation order,
# because the care receiver did not answer any of the calls for a time-critical
# reminder. One position per job; the next is enqueued by whatever ends this
# one -- the webhook, after a pass, an opt-out or no answer -- or straight away
# here when this caregiver cannot be rung at all.
#
# Everything is re-read on every run, as VoiceReminderJob does: the job can sit
# in the queue, be retried, or be reached from a console, and between being
# enqueued and running the dose can be marked done, another caregiver can say
# they are on it, or this one can withdraw.
class EscalationCallJob < ApplicationJob
  queue_as :default

  def perform(occurrence_id, position = 1)
    return unless FeatureFlag.enabled?(:phone_call_reminders) && FeatureFlag.enabled?(:escalation_calls)
    return if position > TelnyxCall::MAX_ESCALATION_POSITIONS

    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence && still_needs_somebody?(occurrence)

    senior = occurrence.reminder.user
    caregiver = CaregiverLink.find_by(senior_id: senior.id, escalation_position: position)&.caregiver

    reason = refusal(caregiver)
    if reason
      Rails.logger.info "Escalation for occurrence #{occurrence.id} skips position #{position}: #{reason}"
      return advance(occurrence, position)
    end

    attempt = TelnyxCall.reserve_escalation(occurrence, caregiver, position)
    if attempt.nil?
      # A row for this position already exists: another run of this job got
      # here first, and the chain is that run's to continue. Otherwise the
      # caregiver is on another call, which is as good as no answer.
      return if occurrence.escalation_calls.exists?(attempt_number: position)

      Rails.logger.info "Escalation for occurrence #{occurrence.id} skips position #{position}: caregiver #{caregiver.id} is on another call"
      return advance(occurrence, position)
    end

    # Re-read after the claim, immediately before the telephone rings: the
    # same gap VoiceReminderJob closes, and here it is the one a caregiver
    # pressing 1 on the previous call -- or the care receiver pressing Done --
    # falls into.
    if !still_needs_somebody?(occurrence.reload) || refusal(caregiver.reload, besides: attempt)
      attempt.update!(status: "cancelled", outcome: "no_response", completed_at: Time.current)
      return advance(occurrence, position) if still_needs_somebody?(occurrence)

      return
    end

    # A call the provider refused rings nobody, so the next person is tried now
    # rather than after the gap.
    advance(occurrence, position) if TelnyxVoiceService.escalate(attempt).nil?
  end

  # Enqueues the next position. Public so the webhook ends a call the same way.
  def self.advance(occurrence, position, wait: nil)
    return if position >= TelnyxCall::MAX_ESCALATION_POSITIONS

    job = wait ? set(wait: wait) : self
    job.perform_later(occurrence.id, position + 1)
  end

  private

  def advance(occurrence, position)
    self.class.advance(occurrence, position)
  end

  # Not done, and nobody has said they will see to it.
  def still_needs_somebody?(occurrence)
    return false if occurrence.status_acknowledged?
    return false unless occurrence.reminder&.critical?

    !occurrence.escalation_calls.exists?(outcome: "accepted")
  end

  # Why this caregiver cannot be rung now, or nil.
  # `besides` is the row this run has just claimed, which must not count
  # against the allowance it is being checked for.
  def refusal(caregiver, besides: nil)
    return "nobody is in that position" if caregiver.nil?
    return "caregiver #{caregiver.id} has not agreed to escalation calls" unless caregiver.escalation_callable?
    return "outside caregiver #{caregiver.id}'s calling hours" unless caregiver.within_calling_hours?

    if TelnyxCall.escalations_in_window(caregiver).where.not(id: besides&.id).count >= TelnyxCall::MAX_ESCALATIONS_PER_DAY
      "caregiver #{caregiver.id} has had #{TelnyxCall::MAX_ESCALATIONS_PER_DAY} escalation calls today"
    end
  end
end
