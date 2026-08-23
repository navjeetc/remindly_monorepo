# Watches for pending reminder occurrences that have reached their scheduled time
# and enqueues a voice call for seniors who have voice reminders enabled.
#
# Runs frequently (e.g., every minute) so a 9:00 AM dose is called at 9:00 AM in
# the senior's timezone. It is deliberately separate from the missed sweep; a
# missed call is not the same as a missed dose.
class VoiceReminderSchedulerJob < ApplicationJob
  queue_as :default

  LOOKAHEAD = 2.minutes

  def perform(now: Time.current)
    # Occurrences that are now due, still pending, for users with a phone and
    # voice reminders turned on, and have not already been called for this
    # occurrence.
    Occurrence
      .status_pending
      .where("occurrences.scheduled_at <= ?", now)
      .joins(reminder: :user)
      .where(users: { voice_reminders_enabled: true })
      .where.not(users: { phone: [ nil, "" ] })
      .where.not(
        id: TelnyxCall.select(:occurrence_id).where("telnyx_calls.created_at > ?", now - LOOKAHEAD)
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
