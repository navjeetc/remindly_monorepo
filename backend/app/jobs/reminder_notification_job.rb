# Delivers caregiver notifications for a reminder occurrence, off the request and
# off the missed sweep.
#
# Both callers commit a one-shot state transition first (pending -> acknowledged
# in the controller, pending -> missed in the sweep) and then enqueue this job.
# Doing the delivery here rather than inline means:
#   - a senior's "taken" request never 500s because a caregiver email failed, and
#     the acknowledgement is already safely committed;
#   - if delivery fails transiently (queue hiccup, a bad recipient), Solid Queue
#     retries this job instead of the alert being lost forever the moment the
#     occurrence left `pending`.
#
# The service's per-caregiver delivery is idempotent, so a retry does not
# re-notify caregivers who already got through.
class ReminderNotificationJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # kind is "acknowledged" or "missed".
  def perform(occurrence_id, kind)
    occurrence = Occurrence.find_by(id: occurrence_id)
    return unless occurrence

    # The occurrence's status may have moved since this was enqueued — a late take
    # flips missed -> acknowledged, for instance. Only deliver if it still reflects
    # the event we were asked to announce, so we never email "missed" for a dose
    # that has since been taken.
    return unless status_matches?(occurrence, kind)

    ReminderNotificationService.public_send("notify_#{kind}", occurrence)
  end

  private

  def status_matches?(occurrence, kind)
    case kind
    when "acknowledged" then occurrence.status_acknowledged?
    when "missed"       then occurrence.status_missed?
    else false
    end
  end
end
