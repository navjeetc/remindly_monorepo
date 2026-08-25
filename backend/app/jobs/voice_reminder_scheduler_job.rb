# Watches for pending reminder occurrences that have reached their scheduled time
# and enqueues a phone call for seniors who have call reminders enabled.
#
# Runs frequently (e.g., every minute) so a 9:00 AM dose is called at 9:00 AM in
# the senior's timezone. It is deliberately separate from the missed sweep; a
# missed call is not the same as a missed dose.
class VoiceReminderSchedulerJob < ApplicationJob
  queue_as :default


  # How stale a reminder may be and still be worth telephoning about.
  #
  # Without a lower bound this matched every pending occurrence ever scheduled,
  # and occurrences do not age out on their own: MarkMissedOccurrencesJob only
  # sweeps within its own MARK_LOOKBACK of seven days, so anything unacknowledged
  # for longer stays pending permanently. One account had accumulated thirty
  # such rows over six months, the oldest from the previous November. Switching
  # this feature on would have telephoned about all of them at once, then again
  # every day, for ever.
  #
  # Two hours is long enough to survive a queue backlog or a delayed sweep, and
  # short enough that nobody is rung at bedtime about a dose due at breakfast.
  # A call is far more intrusive than the status write MarkMissedOccurrencesJob
  # performs, so this window is deliberately much tighter than its.
  LOOKBACK = 2.hours

  # How late a row may be written and still be treated as having come due
  # naturally.
  #
  # Recurrence.expand deliberately back-fills the most recent past slot of the
  # day — its own comment explains why, and the reason is good: it keeps a
  # same-day reminder visible after its clock time has passed, for a caregiver in
  # one timezone setting a reminder for a senior in another. Harmless on a
  # dashboard.
  #
  # Not harmless here. Editing a reminder regenerates its pending occurrences, so
  # the back-filled row is created *now* and dated earlier today — and a row dated
  # inside LOOKBACK is indistinguishable, to the query above, from one that just
  # came due. Editing a reminder at 8pm to ring at 7pm would therefore telephone
  # the senior straight away about a dose whose time had already passed.
  #
  # A minute of grace, because a reminder created for the current minute is a real
  # thing a caregiver does, and the row is written a moment after the time it
  # names.
  BACKFILL_GRACE = 1.minute

  def perform(now: Time.current)
    return unless FeatureFlag.enabled?(:phone_call_reminders)

    # Occurrences that are now due, still pending, for users with a phone and
    # call reminders turned on, and have not already been called for this
    # occurrence.
    Occurrence
      .status_pending
      .where(scheduled_at: (now - LOOKBACK)..now)
      .joins(reminder: :user)
      .where(users: { call_reminders_enabled: true })
      .where.not(users: { phone: [ nil, "" ] })
      .where.not(users: { call_consent_at: nil })
      .where(users: { call_opted_out_at: nil })
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
        # Never telephone about an occurrence that did not exist when its time
        # came. Skipped rather than suppressed: suppress_call! records that a
        # call was withheld, and nothing was withheld here — this row was never
        # due in real time, so there was no call to withhold.
        if occ.created_at > occ.scheduled_at + BACKFILL_GRACE
          # debug, not info: the scheduler runs every minute and this row stays in
          # scope for up to LOOKBACK, so one edit would otherwise print the same
          # line 120 times. The job logs at info when it declines, and that
          # happens once.
          Rails.logger.debug(
            "Voice reminder for occurrence #{occ.id} skipped: back-filled at " \
            "#{occ.created_at.iso8601} for #{occ.scheduled_at.iso8601}, which had already passed"
          )
          next
        end

        # Calling hours are per-person, in their own timezone, so this cannot be
        # a WHERE clause -- every senior's window lands on a different UTC hour.
        # Filtering here rather than letting the job drop it matters because a
        # dose due at 2am stays pending until the missed sweep claims it an hour
        # later, and without this every one of those minutes would enqueue a job
        # that only exists to decline.
        unless occ.reminder.user.within_calling_hours?(at: now)
          # Recorded here, not only in the job. In production the scheduler is
          # the only caller, so skipping straight past meant the refusal was
          # never written down anywhere — and an hour later the caregiver was
          # told the senior had not marked it done, for a call nobody placed.
          occ.suppress_call!(:outside_calling_hours, at: now)
          next
        end

        VoiceReminderJob.perform_later(occ.id)
      end
  end
end
