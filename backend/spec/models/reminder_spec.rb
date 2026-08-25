require "rails_helper"

RSpec.describe Reminder do
  # A reminder is kept in the clock of the person it is for. It used to be kept
  # in whatever clock the caller supplied — RemindersController permits :tz — so
  # a caregiver whose device said New Delhi created New York seniors' reminders
  # stamped "New Delhi". Recurrence expands the schedule in that column, and New
  # Delhi has never observed daylight saving, so the senior's clock moved twice a
  # year and the reminder stayed where it was.
  describe "the clock a reminder is kept in" do
    let(:senior) { create(:user, :senior, name: "Mum", tz: "America/New_York") }

    def reminder_with(attrs = {})
      senior.reminders.create!({ title: "Take meds", category: :medication, rrule: "FREQ=DAILY" }.merge(attrs))
    end

    it "is the senior's, when none is given" do
      expect(reminder_with.tz).to eq("America/New_York")
    end

    # The actual defect. The JSON API permits tz, so this is reachable by any
    # client that sends its own zone.
    it "is the senior's even when the caller insists otherwise" do
      expect(reminder_with(tz: "New Delhi").tz).to eq("America/New_York")
    end

    it "is corrected on save, not only on create" do
      reminder = reminder_with
      reminder.update!(tz: "New Delhi")

      expect(reminder.reload.tz).to eq("America/New_York")
    end

    it "follows the senior when they are in a different zone than the caregiver" do
      pacific = create(:user, :senior, name: "Dad", tz: "America/Los_Angeles")

      expect(pacific.reminders.create!(title: "Pills", category: :medication,
                                       rrule: "FREQ=DAILY", tz: "America/New_York").tz)
        .to eq("America/Los_Angeles")
    end
  end
end
