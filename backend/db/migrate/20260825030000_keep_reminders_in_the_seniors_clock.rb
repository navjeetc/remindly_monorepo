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
# happening. This fixes the rows written before that.
class KeepRemindersInTheSeniorsClock < ActiveRecord::Migration[8.1]
  def up
    Reminder.reset_column_information

    Reminder.includes(:user).find_each do |reminder|
      senior_tz = reminder.user&.tz
      next if senior_tz.blank?
      next if reminder.tz == senior_tz

      # Same zone under a different spelling, which is most of them: reminders
      # carried Rails' friendly names ("Eastern Time (US & Canada)") while users
      # carried IANA ones ("America/New_York"). Normalising the string lets the
      # two columns be compared at all, and changes no schedule, so the
      # occurrences are left alone -- re-expanding them would destroy and rebuild
      # rows to arrive at the identical times.
      if same_zone?(reminder.tz, senior_tz)
        reminder.update_column(:tz, senior_tz)
        next
      end

      # A genuinely different clock. The wall-clock time the caregiver set is
      # start_time read in the senior's zone -- which is what the edit form has
      # always shown them -- and re-stamping the zone preserves exactly that
      # while handing the schedule back to a clock that observes daylight saving.
      say "reminder #{reminder.id} (#{reminder.title.inspect}): #{reminder.tz.inspect} -> #{senior_tz.inspect}"

      # Which pending rows are safe to drop has to be worked out BEFORE the
      # re-stamp, because it is the old schedule they belong to.
      replaceable = replaceable_slots(reminder)

      reminder.update_column(:tz, senior_tz)
      replaceable.each(&:destroy)
      Recurrence.expand(reminder.reload)
    end
  end

  # Deliberately irreversible. Down would have to restore a zone that was wrong,
  # and re-drift the schedules that were repaired.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # Pending occurrences the corrected schedule can rebuild, and nothing else.
  #
  # The drifted ones have to go: expand() only ever creates, so without this they
  # survive beside the corrected ones and the senior is reminded twice, an hour
  # apart. But "pending" is not the same as "replaceable", and deleting on status
  # alone destroys three things it should not:
  #
  #   - a live snooze. Occurrence#snooze! materialises a one-off pending row at
  #     the snoozed time, which is not an RRULE slot, so expand would never
  #     recreate it. Deleting it silently cancels the snooze a senior asked for.
  #   - delivery history. Occurrence has_many :telnyx_calls, dependent: :destroy,
  #     so the cascade takes the record of every call placed about that dose --
  #     the audit trail the consent design exists to keep.
  #   - acknowledgements, by the same cascade.
  #
  # So: only rows that sit exactly on a slot of the *old* schedule, and that
  # nothing has happened to. Anything else is somebody's state, not our cache.
  def replaceable_slots(reminder)
    pending = reminder.occurrences.where(status: :pending)
                      .where.missing(:telnyx_calls).where.missing(:acknowledgements).to_a
    return [] if pending.empty?

    zone = ActiveSupport::TimeZone[reminder.tz.to_s] || Time.zone
    schedule = IceCube::Schedule.new((reminder.start_time || pending.first.scheduled_at).in_time_zone(zone))
    schedule.add_recurrence_rule(IceCube::Rule.from_ical(reminder.rrule))

    span = pending.map(&:scheduled_at).minmax
    slots = schedule.occurrences_between(span.first - 1.day, span.last + 1.day).map { |t| t.to_i }.to_set

    pending.select { |o| slots.include?(o.scheduled_at.to_i) }
  rescue StandardError => e
    # An RRULE IceCube cannot parse is not a reason to abort a deploy, and it is
    # not a reason to guess either. Leave those rows alone; the duplicate is
    # visible and recoverable, a deleted snooze is neither.
    say "  could not compute replaceable slots for reminder #{reminder.id} (#{e.class}); leaving its occurrences alone"
    []
  end

  def same_zone?(one, other)
    a = ActiveSupport::TimeZone[one.to_s]
    b = ActiveSupport::TimeZone[other.to_s]
    a.present? && b.present? && a.tzinfo.name == b.tzinfo.name
  end
end
