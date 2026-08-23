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

    TelnyxVoiceService.dial(occurrence)
  end
end
