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

    Reminder.find_each do |reminder|
      senior_tz = User.find_by(id: reminder.user_id)&.tz
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
      #
      # The pending occurrences have to go. expand() only ever creates, so
      # without this the drifted ones survive beside the corrected ones and the
      # senior is reminded twice, an hour apart. Resolved occurrences are kept:
      # they are the record of what actually happened.
      say "reminder #{reminder.id} (#{reminder.title.inspect}): #{reminder.tz.inspect} -> #{senior_tz.inspect}"
      reminder.update_column(:tz, senior_tz)
      reminder.occurrences.where(status: :pending).destroy_all
      Recurrence.expand(reminder.reload)
    end
  end

  # Deliberately irreversible. Down would have to restore a zone that was wrong,
  # and re-drift the schedules that were repaired.
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
