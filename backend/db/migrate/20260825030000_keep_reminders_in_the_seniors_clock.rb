# Repairs reminders stamped with somebody else's clock.
#
# RemindersController permits :tz in reminder_params, so the JSON API took
# whatever zone the calling device sent. A caregiver whose own device said New
# Delhi created New York seniors' reminders stamped "New Delhi", and nothing
# corrected them afterwards. Recurrence expands the schedule in that column, so
# those reminders were pinned to a zone that has never observed daylight saving:
# the senior's clock moved twice a year and the reminder did not.
#
# Reminder now keeps tz equal to its user's on every write, which stops new ones
# happening. This normalises the spellings, and reports — without touching —
# the rows whose clock is genuinely somebody else's, because repairing one of
# those safely means reconciling its occurrences too. See the comment on that
# branch below.
class KeepRemindersInTheSeniorsClock < ActiveRecord::Migration[8.1]
  def up
    Reminder.reset_column_information
    stranded = []

    Reminder.includes(:user).find_each do |reminder|
      senior_tz = reminder.user&.tz
      next if senior_tz.blank?
      next if reminder.tz == senior_tz

      # Same zone under a different spelling, which is most of them: reminders
      # carried Rails' friendly names ("Eastern Time (US & Canada)") while users
      # carried IANA ones ("America/New_York"). Normalising the string lets the
      # two columns be compared at all, and changes no schedule — the clock is
      # identical, so every occurrence stays exactly where it was.
      if same_zone?(reminder.tz, senior_tz)
        reminder.update_column(:tz, senior_tz)
        next
      end

      stranded << reminder
    end

    # A genuinely different clock is reported, not repaired.
    #
    # Repairing one means reconciling two schedules: re-stamping the zone, then
    # deciding what becomes of occurrences already materialised at the old times.
    # Some of those carry state expand cannot rebuild — a snooze, a call, a
    # suppression, an acknowledgement — and the corrected schedule lands slots
    # beside them, so the senior is reminded twice and the caregiver is told a
    # dose was missed that was marked done. Pairing an old dose with its
    # corrected counterpart looked tractable and is not: the offset between two
    # arbitrary zones can exceed the interval the reminder recurs at, so nearness
    # cannot identify the pair and no rule short of walking both schedules will.
    #
    # That is a tool somebody runs and reads the output of, not a migration that
    # deletes rows unattended during a deploy. Tracked separately. The model rule
    # this migration ships alongside means no new row can arrive in this state,
    # and saving one of these reminders repairs it.
    return if stranded.empty?

    say "#{stranded.size} reminder(s) are stamped with a clock that is not their senior's."
    say "They are left untouched: repairing one safely needs its occurrences reconciled too."
    stranded.each do |reminder|
      say "  reminder #{reminder.id} (#{reminder.title.inspect}) for user #{reminder.user_id}: " \
          "#{reminder.tz.inspect} vs #{reminder.user.tz.inspect}"
    end
  end

  # Deliberately irreversible. Down would restore spellings that were wrong.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def same_zone?(one, other)
    a = ActiveSupport::TimeZone[one.to_s]
    b = ActiveSupport::TimeZone[other.to_s]
    a.present? && b.present? && a.tzinfo.name == b.tzinfo.name
  end
end
