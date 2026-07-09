require 'rails_helper'

RSpec.describe Recurrence do
  include ActiveSupport::Testing::TimeHelpers

  let(:tz) { "America/New_York" }
  let(:senior) { create(:user, :senior, tz: tz) }

  # 5:30 PM in the reminder's timezone — well past a morning reminder.
  let(:afternoon) { ActiveSupport::TimeZone[tz].local(2026, 7, 9, 17, 30, 0) }

  around do |example|
    travel_to(afternoon) { example.run }
  end

  describe ".expand" do
    context "with a once-daily reminder whose time has already passed today" do
      let(:reminder) do
        senior.reminders.create!(
          title: "Morning pills",
          rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0",
          tz: tz
        )
      end

      it "still creates today's occurrence so it is not silently dropped" do
        Recurrence.expand(reminder)

        today_nine = ActiveSupport::TimeZone[tz].local(2026, 7, 9, 9, 0, 0)
        expect(reminder.occurrences.where(scheduled_at: today_nine)).to exist
      end

      it "also creates tomorrow's upcoming occurrence" do
        Recurrence.expand(reminder)

        tomorrow_nine = ActiveSupport::TimeZone[tz].local(2026, 7, 10, 9, 0, 0)
        expect(reminder.occurrences.where(scheduled_at: tomorrow_nine)).to exist
      end
    end

    context "with an hourly reminder opened for the first time in the afternoon" do
      let(:reminder) do
        senior.reminders.create!(
          title: "Drink water",
          rrule: "FREQ=HOURLY",
          tz: tz,
          start_time: ActiveSupport::TimeZone[tz].local(2026, 7, 9, 0, 0, 0)
        )
      end

      it "does not backfill every earlier hour of the day" do
        Recurrence.expand(reminder)

        today_start = ActiveSupport::TimeZone[tz].local(2026, 7, 9, 0, 0, 0)
        past_today = reminder.occurrences.where(scheduled_at: today_start...afternoon)

        # Only the most recent past slot (5 PM) should be materialized, not the
        # 17 earlier hours of the day.
        five_pm = ActiveSupport::TimeZone[tz].local(2026, 7, 9, 17, 0, 0)
        expect(past_today.count).to eq(1)
        expect(past_today.first.scheduled_at).to eq(five_pm)
      end

      it "still creates upcoming occurrences" do
        Recurrence.expand(reminder)

        six_pm = ActiveSupport::TimeZone[tz].local(2026, 7, 9, 18, 0, 0)
        expect(reminder.occurrences.where(scheduled_at: six_pm)).to exist
      end
    end

    context "when the current occurrence was already acknowledged" do
      let(:reminder) do
        senior.reminders.create!(
          title: "Morning pills",
          rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0",
          tz: tz
        )
      end
      let(:today_nine) { ActiveSupport::TimeZone[tz].local(2026, 7, 9, 9, 0, 0) }

      it "does not reset it back to pending" do
        reminder.occurrences.create!(scheduled_at: today_nine, status: :acknowledged)

        Recurrence.expand(reminder)

        occurrence = reminder.occurrences.find_by!(scheduled_at: today_nine)
        expect(occurrence).to be_status_acknowledged
        expect(reminder.occurrences.where(scheduled_at: today_nine).count).to eq(1)
      end
    end
  end
end
