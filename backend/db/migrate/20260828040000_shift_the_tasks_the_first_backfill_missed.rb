# frozen_string_literal: true

# ShiftTaskTimesIntoTheSeniorsClock excluded recurring templates with
# `rrule: nil`, which is `rrule IS NULL` in SQL. The task form submits an empty
# string for a one-off task rather than leaving the column NULL, so two
# perfectly ordinary appointments in production were read as "not matching the
# scope" and left with the wrong time — including the one that prompted the
# original fix.
#
# A template is a row whose rrule is *present*. Blank and NULL both mean "not
# recurring", and only the second was treated that way.
#
# This shifts exactly the rows that were missed: blank-but-not-NULL rrule, same
# exclusions otherwise. Rows the first migration already corrected have a NULL
# rrule and cannot be caught twice by this scope.
class ShiftTheTasksTheFirstBackfillMissed < ActiveRecord::Migration[8.1]
  # The corrected parser shipped in the *same* deploy as the first migration, so
  # anything created or resaved since then already stores a correct absolute
  # instant — and, being a one-off, also carries a blank rrule. Without this
  # bound the scope below would read those correct rows as wall clock and move
  # them by the senior's offset, which is the failure this whole sequence
  # exists to stop.
  #
  # Production had one such row within minutes of the deploy: a dentist
  # appointment stored correctly at 13:00 UTC for 9am Eastern. It must not move.
  #
  # `update_columns` does not touch `updated_at`, so rows the first migration
  # corrected keep their original timestamp and are not hidden by this bound —
  # they are excluded by their NULL rrule instead.
  CORRECTED_AT = Time.utc(2026, 8, 28, 3, 0, 0)

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

    scope = MigrationTask.where(external_source: nil, parent_task_id: nil, rrule: "")
    too_new = scope.where(updated_at: CORRECTED_AT..).count
    say "skipping #{too_new} blank-rrule task(s) touched since the parser fix" if too_new.positive?

    scope.where(updated_at: ...CORRECTED_AT).find_each do |task|
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

    say "shifted #{shifted} task(s) the first backfill missed, skipped #{skipped}"
  end
end
