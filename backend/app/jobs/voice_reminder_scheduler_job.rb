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
      .find_each do |occ|
        VoiceReminderJob.perform_later(occ.id)
      end
  end
end
