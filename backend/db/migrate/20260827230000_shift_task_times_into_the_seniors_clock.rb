# Until this shipped, the task form's wall-clock text ("2026-08-28T15:00", no
# zone in it) was cast in UTC, because Time.zone is UTC app-wide. So a
# caregiver typing 3pm for a senior in New York stored 15:00 UTC — 11am where
# she actually is, and that is the time her own dashboard showed her.
#
# The caregiver's task list hid it by printing the raw instant back, so the two
# screens disagreed by exactly the senior's offset. TasksController now reads
# the text in the senior's clock; this repairs what was stored before it did.
#
# The repair is to take the wall clock already sitting in the column and re-read
# it in the senior's zone: 15:00 UTC becomes 15:00 New York. Nothing is deleted
# and nothing is created — every row is shifted or skipped, and `down` shifts
# back — because a migration that removes task history is not one worth having.
class ShiftTaskTimesIntoTheSeniorsClock < ActiveRecord::Migration[8.0]
  class MigrationTask < ActiveRecord::Base
    self.table_name = "tasks"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    shift { |naive, zone| zone.local(naive.year, naive.month, naive.day, naive.hour, naive.min, naive.sec) }
  end

  def down
    shift { |naive, zone| naive.in_time_zone(zone).then { |l| Time.utc(l.year, l.month, l.day, l.hour, l.min, l.sec) } }
  end

  private

  def shift
    zones = MigrationUser.pluck(:id, :tz).to_h
    shifted = skipped = 0

    MigrationTask.where(external_source: nil).find_each do |task|
      # An external calendar hands us a real instant, not typed text, so those
      # rows were never wrong — the scope above leaves them out.
      zone = ActiveSupport::TimeZone[zones[task.senior_id].to_s]
      if zone.nil?
        skipped += 1
        next
      end

      updates = {}
      %i[scheduled_at start_time].each do |column|
        naive = task[column]
        next if naive.blank?

        updates[column] = yield(naive.utc, zone)
      end

      if updates.any?
        task.update_columns(updates)
        shifted += 1
      else
        skipped += 1
      end
    end

    say "shifted #{shifted} task(s) into the senior's clock, skipped #{skipped}"
  end
end
