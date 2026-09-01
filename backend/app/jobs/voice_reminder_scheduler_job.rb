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

  # How far back the refusal sweep looks, and deliberately not LOOKBACK.
  #
  # LOOKBACK answers "is this still worth telephoning about". This answers "can
  # somebody still be told about this", and the missed email reaches further back
  # than the telephone does: MarkMissedOccurrencesJob closes an occurrence GRACE
  # after its time and emails about anything due inside NOTIFY_WINDOW. The rows
  # that can produce a caregiver email are therefore the ones due between one and
  # three hours ago — and LOOKBACK sees only two of those three hours.
  #
  # A reminder edited at 6pm whose slot was 3:30pm landed in the missing hour:
  # back-filled, never seen by the call query, so nothing recorded, so the
  # caregiver was told the care receiver had not marked it done. Which is the
  # sentence this file was changed to stop sending, an hour to the left of where
  # it was fixed. Derived from NOTIFY_WINDOW rather than written as 3.hours, so
  # widening that window cannot leave this one behind.
  SUPPRESSION_LOOKBACK = MarkMissedOccurrencesJob::NOTIFY_WINDOW

  def perform(now: Time.current)
    return unless FeatureFlag.enabled?(:phone_call_reminders)

    record_back_filled_refusals(now)
    place_due_calls(now)
  end

  private

  def place_due_calls(now)
    # Occurrences that are now due, still pending, for users with a phone and
    # call reminders turned on, and have not already been called for this
    # occurrence.
    for_seniors_taking_calls(Occurrence.status_pending)
      .where(scheduled_at: (now - LOOKBACK)..now)
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
        # came. A row dated inside LOOKBACK is indistinguishable, to the query
        # above, from one that has just come due: editing a reminder at 8pm to
        # ring at 7pm would otherwise telephone the senior straight away about a
        # dose whose time had already passed.
        #
        # Only the enqueue is refused here. The reason was written down by the
        # sweep above, which looks further back than this query does — so every
        # row this query can reach has already been through it.
        next if back_filled?(occ)

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

  # Write the refusal down for every back-filled row a caregiver could still be
  # emailed about.
  #
  # Its own pass rather than a branch inside the loop above, because the two are
  # answering different questions over different windows — see
  # SUPPRESSION_LOOKBACK. #86 refused these rows and recorded nothing, reasoning
  # that suppress_call! notes a call was withheld and nothing was withheld: the
  # row was never due in real time. The reasoning holds and the consequence did
  # not. With nothing recorded, phone_failure_reason returns nil, the missed
  # email falls through to the wording written for the web client, and a
  # caregiver who moved a dose to a time already past is told the care receiver
  # had not marked it done. Nobody was telephoned, and the row existed only after
  # its own due time.
  #
  # Restricted to seniors who take calls, for the reason the mailer is careful
  # about too: a phone failure is not a story to tell about somebody whose
  # channel is the screen.
  #
  # Rows already carrying a decision are left out of the query rather than
  # re-examined, so a single edit writes one row and logs one line, instead of
  # being reconsidered every minute for the next three hours.
  def record_back_filled_refusals(now)
    for_seniors_taking_calls(Occurrence.status_pending)
      .where(scheduled_at: (now - SUPPRESSION_LOOKBACK)..now, call_suppressed_at: nil)
      .find_each do |occ|
        next unless back_filled?(occ)

        # at: now, matching the outside_calling_hours suppression. The job takes
        # its clock as an argument and every decision it makes should be dated by
        # that clock, or a run driven with a simulated time records refusals
        # stamped with the wall clock instead.
        occ.suppress_call!(:added_after_its_time, at: now)

        Rails.logger.info(
          "Voice reminder for occurrence #{occ.id} refused: back-filled at " \
          "#{occ.created_at.iso8601} for #{occ.scheduled_at.iso8601}, which had already passed"
        )
      end
  end

  # The SQL half of User#callable_by_phone?. Written once and shared by both
  # passes: a condition dropped from one of them is a call placed to somebody who
  # opted out, or a phone failure reported about somebody who never gave a number.
  def for_seniors_taking_calls(relation)
    relation
      .joins(reminder: :user)
      .where(users: { call_reminders_enabled: true, call_opted_out_at: nil })
      .where.not(users: { phone: [ nil, "" ] })
      .where.not(users: { call_consent_at: nil })
  end

  # The row was written after the time it names, so nothing came due when the
  # clock reached it -- there was nothing there to come due.
  def back_filled?(occ)
    occ.created_at > occ.scheduled_at + BACKFILL_GRACE
  end
end
