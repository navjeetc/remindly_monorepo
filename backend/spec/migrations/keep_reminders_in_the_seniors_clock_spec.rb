require "rails_helper"
require Rails.root.join("db/migrate/20260825030000_keep_reminders_in_the_seniors_clock.rb")

# What this migration does, and — more importantly — what it declines to do.
#
# Repairing a genuinely mismatched clock means reconciling the occurrences
# already materialised at the old times, some of which carry state expand cannot
# rebuild. Four separate attempts at that rule were each wrong in a different
# way, so the migration reports those rows and leaves them alone. Tracked
# separately; these specs pin that it really does leave them alone.
RSpec.describe KeepRemindersInTheSeniorsClock do
  include ActiveSupport::Testing::TimeHelpers

  let(:eastern) { ActiveSupport::TimeZone["America/New_York"] }
  let(:senior) { create(:user, :senior, name: "Mum", tz: "America/New_York") }

  # Restored to whatever it was, not to true. Assuming the prior value makes the
  # suite order-dependent: whichever spec runs after this one inherits our guess
  # rather than its own setting.
  around do |example|
    was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = was
  end

  describe "a zone that differs only in spelling" do
    it "is normalised, so the two columns can be compared at all" do
      reminder = senior.reminders.create!(title: "Pills", category: :medication, rrule: "FREQ=DAILY",
                                          start_time: eastern.local(2026, 8, 20, 9, 0))
      reminder.update_column(:tz, "Eastern Time (US & Canada)")

      described_class.new.up

      expect(reminder.reload.tz).to eq("America/New_York")
    end

    it "leaves every occurrence exactly where it was, the clock being identical" do
      reminder = senior.reminders.create!(title: "Pills", category: :medication, rrule: "FREQ=DAILY",
                                          start_time: eastern.local(2026, 8, 20, 9, 0))
      reminder.update_column(:tz, "Eastern Time (US & Canada)")
      Recurrence.expand(reminder.reload)
      before = reminder.occurrences.pluck(:id, :scheduled_at).sort

      described_class.new.up

      expect(reminder.occurrences.reload.pluck(:id, :scheduled_at).sort).to eq(before)
    end
  end

  describe "a clock that is genuinely somebody else's" do
    # Anchored in November, as the production rows were: 8:41pm EST is 01:41 UTC,
    # New Delhi holds that instant all year, and in August it reads 9:41pm
    # Eastern. An August-anchored fixture does not drift at all in August.
    let(:drifted) do
      senior.reminders.create!(title: "Take sleep medicine", category: :medication, rrule: "FREQ=DAILY",
                               start_time: eastern.local(2025, 11, 26, 20, 41))
            .tap { |r| r.update_column(:tz, "New Delhi") }
    end

    it "is left stamped as it was, rather than half-repaired" do
      described_class.new.up

      expect(drifted.reload.tz).to eq("New Delhi")
    end

    it "keeps its occurrences, including anything already answered" do
      travel_to(eastern.local(2026, 8, 21, 22, 0)) do
        Recurrence.expand(drifted)
        done = drifted.occurrences.first
        done.update!(status: :acknowledged)
        Acknowledgement.create!(occurrence: done, kind: "taken", at: Time.current)
        before = drifted.occurrences.pluck(:id).sort

        described_class.new.up

        expect(drifted.occurrences.reload.pluck(:id).sort).to eq(before)
        expect(done.reload.status).to eq("acknowledged")
      end
    end

    # The model rule is what actually repairs these: saving the reminder for any
    # reason re-stamps it, which is a caregiver editing it or any other write.
    it "is repaired by the model the moment anything saves it" do
      drifted.update!(title: "Take sleep medicine")

      expect(drifted.reload.tz).to eq("America/New_York")
    end
  end
end
