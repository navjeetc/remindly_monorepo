# Watches for pending reminder occurrences that have reached their scheduled time
# and enqueues a voice call for seniors who have voice reminders enabled.
#
# Runs frequently (e.g., every minute) so a 9:00 AM dose is called at 9:00 AM in
# the senior's timezone. It is deliberately separate from the missed sweep; a
# missed call is not the same as a missed dose.
class VoiceReminderSchedulerJob < ApplicationJob
  queue_as :default


  def perform(now: Time.current)
    return unless FeatureFlag.enabled?(:phone_call_reminders)

    # Occurrences that are now due, still pending, for users with a phone and
    # voice reminders turned on, and have not already been called for this
    # occurrence.
    Occurrence
      .status_pending
      .where("occurrences.scheduled_at <= ?", now)
      .joins(reminder: :user)
      .where(users: { voice_reminders_enabled: true })
      .where.not(users: { phone: [ nil, "" ] })
      # Skip what cannot be dialled yet or any more. Correctness does not rest on
      # this -- TelnyxCall.reserve refuses the same cases atomically, and must,
      # because two runs can pass these checks simultaneously. This is here so
      # the common case does not enqueue jobs that exist only to decline.
      #
      # Both clauses are per-occurrence rather than a single "called recently"
      # window. The window alone was the bug: attempts reused one row, so its
      # created_at never advanced and an unanswered senior was re-dialled every
      # minute for the full hour before the missed sweep closed the occurrence.
      .where.not(
        id: TelnyxCall.select(:occurrence_id)
          .where("telnyx_calls.created_at > ?", now - TelnyxCall::RETRY_AFTER)
      )
      .where.not(
        id: TelnyxCall.select(:occurrence_id)
          .group(:occurrence_id)
          .having("COUNT(*) >= ?", TelnyxCall::MAX_ATTEMPTS)
      )
      .includes(reminder: :user)
      .find_each do |occ|
        # Calling hours are per-person, in their own timezone, so this cannot be
        # a WHERE clause -- every senior's window lands on a different UTC hour.
        # Filtering here rather than letting the job drop it matters because a
        # dose due at 2am stays pending until the missed sweep claims it an hour
        # later, and without this every one of those minutes would enqueue a job
        # that only exists to decline.
        next unless occ.reminder.user.within_calling_hours?(at: now)

        VoiceReminderJob.perform_later(occ.id)
      end
  end
end
