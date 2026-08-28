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

    # Only rows the web form could have produced. Everything excluded here was
    # already storing a correct absolute instant, and shifting it would break
    # data that was never wrong:
    #
    #   external_source  a synced calendar hands us a real instant
    #   parent_task_id   Recurrence.expand_task generates children from IceCube
    #                    in the senior's zone — already absolute, and it does
    #                    not set external_source, so nothing else excludes them
    #   rrule            a template's children are already correct; shifting the
    #                    template's start_time would desynchronise it from them
    #
    # One gap is honest to state: Api::TasksController#create accepts ISO-8601
    # instants and sets none of these columns, so an API-created one-off is
    # indistinguishable here. Production was checked before this shipped and
    # contains none — all five affected rows are one-off form tasks. Any
    # environment where that is not true should check before migrating, which
    # is why every shifted row is logged below rather than counted silently.
    scope = MigrationTask.where(external_source: nil, parent_task_id: nil, rrule: nil)

    scope.find_each do |task|
      # Prefer the task's own clock, matching Task#zone, and fall back to the
      # person it is for.
      zone = ActiveSupport::TimeZone[task[:tz].to_s] ||
             ActiveSupport::TimeZone[zones[task.senior_id].to_s]
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
        say "  task #{task.id}: #{task[:scheduled_at]} -> #{updates[:scheduled_at]}" if updates[:scheduled_at]
        task.update_columns(updates)
        shifted += 1
      else
        skipped += 1
      end
    end

    say "shifted #{shifted} task(s) into the senior's clock, skipped #{skipped}"
  end
end
