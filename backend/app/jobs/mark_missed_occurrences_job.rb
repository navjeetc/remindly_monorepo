# Marks reminder occurrences missed once their scheduled time has passed without
# acknowledgement, and alerts caregivers about the medication ones.
#
# Nothing in the app used to write the `missed` status at all — the enum and the
# dashboard counters existed, but every occurrence stayed `pending` forever, so
# the "missed" tallies always read zero. This sweep is what actually populates
# that state.
#
# Marking and alerting are deliberately separated:
#
#   GRACE          how long after the due time we wait before calling it missed,
#                  so a senior taking their pill a few minutes late is not reported.
#
#   MARK_LOOKBACK  how far back we still mark. It is generous so the dashboard's
#                  missed counts stay honest and a queue outage does not skip
#                  occurrences forever — after downtime the next run still marks
#                  everything within the window. It is bounded (not unbounded) only
#                  so the very first run doesn't rewrite the entire history at once.
#
#   NOTIFY_WINDOW  how recently-due a miss must be to *email* about it. A
#                  medication alert that is hours stale is noise, and this keeps the
#                  first run — or recovery after an outage — from emailing a
#                  caregiver about a whole backlog of old doses in one burst.
class MarkMissedOccurrencesJob < ApplicationJob
  queue_as :default

  GRACE = 60.minutes
  MARK_LOOKBACK = 7.days
  NOTIFY_WINDOW = 3.hours

  def perform(now: Time.current)
    cutoff = now - GRACE

    Occurrence
      .status_pending
      .where(scheduled_at: (now - MARK_LOOKBACK)..cutoff)
      .find_each do |occ|
      # Compare-and-swap: only the run that actually flips pending -> missed
      # proceeds. If an acknowledgement moved the row first, update_all matches
      # nothing and we neither overwrite it nor send a contradictory missed alert.
      changed = Occurrence.status_pending.where(id: occ.id)
        .update_all(status: Occurrence.statuses[:missed], updated_at: now)
      next if changed.zero?

      # Marked missed for the dashboard's sake, but only alert on recently-due
      # misses.
      next if occ.scheduled_at < now - NOTIFY_WINDOW

      # Re-read before alerting: a late acknowledgement arriving between the swap
      # above and here would have flipped the row back out of missed, and we
      # should not email that it was missed.
      occ.reload
      next unless occ.status_missed?

      ReminderNotificationService.notify_missed(occ)
    rescue => e
      Rails.logger.error "Failed to mark occurrence #{occ.id} missed: #{e.full_message}"
    end
  end
end
