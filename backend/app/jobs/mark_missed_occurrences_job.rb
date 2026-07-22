# Marks reminder occurrences missed once their scheduled time has passed without
# acknowledgement, and notifies caregivers about the medication ones.
#
# Nothing in the app used to write the `missed` status at all — the enum and the
# dashboard counters existed, but every occurrence stayed `pending` forever, so
# the "missed" tallies always read zero. This sweep is what actually populates
# that state.
#
# Two windows bound the work:
#   GRACE      how long after the due time we wait before calling it missed, so a
#              senior taking their pill a few minutes late is not reported.
#   LOOKBACK   how far back we look. Without it, the first run in production would
#              mark every historical pending occurrence missed at once and email a
#              caregiver about medication that was due months ago. We only ever
#              consider occurrences due within the last day.
class MarkMissedOccurrencesJob < ApplicationJob
  queue_as :default

  GRACE = 60.minutes
  LOOKBACK = 24.hours

  def perform(now: Time.current)
    cutoff = now - GRACE
    horizon = now - LOOKBACK

    scope = Occurrence
      .status_pending
      .where(scheduled_at: horizon..cutoff)

    scope.find_each do |occ|
      # Guard against a concurrent acknowledgement: only act if this call is the
      # one that flips pending -> missed. update_all returns the rows changed.
      changed = Occurrence.status_pending.where(id: occ.id).update_all(status: Occurrence.statuses[:missed])
      next if changed.zero?

      ReminderNotificationService.notify_missed(occ.reload)
    rescue => e
      Rails.logger.error "Failed to mark occurrence #{occ.id} missed: #{e.message}"
    end
  end
end
