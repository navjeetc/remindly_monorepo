require "rails_helper"

# Solid Queue's own schedule parser, and a transitive dependency rather than one
# this app requires anywhere — so it needs asking for by name here.
require "fugit"

# Guards config/recurring.yml, where a mistake is silent by construction.
#
# A schedule that does not parse, or a class that does not exist, does not raise
# anywhere a person would see it — the task simply never runs, which looks
# exactly like a feature nobody uses. This project has twice shipped a
# background failure that presented as silence: Solid Queue not running at all
# (PR #41), and CheckCoverageGapsJob failing every morning for sixteen days.
RSpec.describe "config/recurring.yml" do
  let(:tasks) { YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production") }

  it "defines the jobs the app depends on" do
    expect(tasks.keys).to include(
      "check_coverage_gaps",
      "mark_missed_occurrences",
      "prune_analytics",
      "clear_solid_queue_finished_jobs"
    )
  end

  it "gives every task a schedule Fugit can parse" do
    tasks.each do |key, task|
      schedule = task["schedule"]

      expect(schedule).to be_present, "#{key} has no schedule"
      expect(Fugit.parse(schedule)).to be_present,
        "#{key}: #{schedule.inspect} does not parse, so the task would never run"
    end
  end

  it "names a real job class, or a command, for every task" do
    tasks.each do |key, task|
      next if task["command"].present?

      class_name = task["class"]
      expect(class_name).to be_present, "#{key} has neither a class nor a command"
      expect { class_name.constantize }.not_to raise_error,
        "#{key}: #{class_name} does not exist, so the task would never run"
    end
  end

  # Schedules here are UTC — config.time_zone is left at its default, so
  # Time.zone is UTC in production. Writing "8am" meaning the recipient's
  # morning is the mistake this asserts against: it put a message about a
  # parent's care gap into caregivers' inboxes at 4am Eastern and 1am Pacific.
  describe "the coverage gap email" do
    let(:schedule) { Fugit.parse(tasks.fetch("check_coverage_gaps").fetch("schedule")) }

    def next_run_in(zone, from:)
      schedule.next_time(from).to_utc_time.in_time_zone(zone)
    end

    it "arrives in the morning for US recipients, not the middle of the night" do
      # Checked in both halves of the year, because a fixed UTC hour drifts by
      # an hour across daylight saving and "morning" has to survive that.
      [ Time.utc(2026, 8, 1), Time.utc(2027, 1, 15) ].each do |from|
        eastern = next_run_in("America/New_York", from: from)
        pacific = next_run_in("America/Los_Angeles", from: from)

        expect(eastern.hour).to be_between(7, 9),
          "Eastern recipients would get this at #{eastern.strftime('%-I%p %Z')}"
        expect(pacific.hour).to be >= 4,
          "Pacific recipients would get this at #{pacific.strftime('%-I%p %Z')}"
      end
    end
  end
end
