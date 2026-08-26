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

  # The bug this guards against: a reminder stamped with a zone that never
  # observes daylight saving is pinned to a fixed UTC instant, so the senior's
  # clock moves twice a year and the reminder does not. Two on the production
  # account had drifted an hour, and one had drifted past 9pm — out of the
  # calling window — where it would silently have stopped ringing at all.
  describe "a daily reminder either side of the autumn clock change" do
    # US daylight saving ends on the first Sunday of November: 1 November 2026.
    let(:eastern) { ActiveSupport::TimeZone["America/New_York"] }
    let(:before_the_change) { eastern.local(2026, 10, 30, 12, 0) }
    let(:after_the_change)  { eastern.local(2026, 11, 3, 12, 0) }

    let(:evening_reminder) do
      senior.reminders.create!(title: "Take sleep medicine", category: :medication,
                               rrule: "FREQ=DAILY", start_time: eastern.local(2026, 10, 30, 20, 41))
    end

    # travel_to without a block: this file already travels in an around hook, and
    # nesting the block form is rejected outright by ActiveSupport.
    def evening_times_around(moment)
      travel_to(moment)
      described_class.expand(evening_reminder.reload)
      evening_reminder.occurrences.reload.map { |o| o.scheduled_at.in_time_zone("America/New_York").strftime("%-l:%M%P") }.uniq
    end

    it "still says 8:41pm in October" do
      expect(evening_times_around(before_the_change)).to eq([ "8:41pm" ])
    end

    it "still says 8:41pm in November, when the clocks have gone back" do
      evening_times_around(before_the_change)

      expect(evening_times_around(after_the_change)).to eq([ "8:41pm" ])
    end

    it "moves in UTC to stay put locally, which is the whole point" do
      travel_to(before_the_change)
      described_class.expand(evening_reminder.reload)
      october = evening_reminder.occurrences.reload.last.scheduled_at.utc.strftime("%H:%M")

      evening_reminder.occurrences.destroy_all
      travel_to(after_the_change)
      described_class.expand(evening_reminder.reload)
      november = evening_reminder.occurrences.reload.last.scheduled_at.utc.strftime("%H:%M")

      expect(october).to eq("00:41")   # 8:41pm EDT
      expect(november).to eq("01:41")  # 8:41pm EST — an hour later in UTC, same hour to the senior
    end
  end

  # Reminder keeps tz equal to its user's now, so this shape can only arrive from
  # a row written before that rule existed. expand still honours the stamp — see
  # the comment there for why preferring the user would answer the moving-senior
  # question by accident — so such a row keeps drifting until the repair
  # migration reaches it, which happens at deploy. The senior's zone is a
  # fallback, for a stamp that does not resolve at all.
  describe "a legacy reminder carrying somebody else's clock" do
    # Note this passes under either precedence: within a single DST season a New
    # Delhi stamp and an Eastern one render the same wall-clock time. It is here
    # to show the ordinary case is unaffected, not to pin the precedence — the
    # spec below the next one does that, across the clock change.
    it "is scheduled at the same wall-clock time within a single season" do
      reminder = senior.reminders.create!(title: "Pills", category: :medication,
                                          rrule: "FREQ=DAILY",
                                          start_time: ActiveSupport::TimeZone[tz].local(2026, 7, 9, 8, 39))
      reminder.update_column(:tz, "New Delhi")

      described_class.expand(reminder.reload)

      expect(reminder.occurrences.reload.map { |o| o.scheduled_at.in_time_zone(tz).strftime("%-l:%M%P") }.uniq)
        .to eq([ "8:39am" ])
    end

    # Still expanded in the stamped zone, and deliberately so — which means such a
    # row goes on drifting until the repair migration reaches it. That migration
    # runs from the Docker entrypoint before the app serves a request, so the
    # window is a deploy rather than a season, and its own specs cover the repair.
    #
    # The alternative, preferring the user's zone here, quietly answers a question
    # this change has no business answering: a senior editing their profile
    # timezone would leave every reminder stamped with the old zone, and the next
    # dashboard load would expand in the new one without removing what the old one
    # had materialised — a second row an hour away from the first, and with phone
    # reminders on, two calls for one tablet.
    it "keeps using the stamped zone, leaving the repair to the migration" do
      eastern = ActiveSupport::TimeZone["America/New_York"]
      reminder = senior.reminders.create!(title: "Take sleep medicine", category: :medication,
                                          rrule: "FREQ=DAILY",
                                          start_time: eastern.local(2026, 10, 30, 20, 41))
      reminder.update_column(:tz, "New Delhi")

      travel_to(eastern.local(2026, 11, 3, 12, 0))
      described_class.expand(reminder.reload)

      # 8:41pm EDT is 00:41 UTC; New Delhi never changes, so November keeps that
      # instant and the senior's evening has moved an hour away from it.
      expect(reminder.occurrences.reload.map { |o| o.scheduled_at.in_time_zone("America/New_York").strftime("%-l:%M%P") }.uniq)
        .to eq([ "7:41pm" ])
    end

    # A senior changing their own timezone must not silently double their
    # reminders. Nothing here re-stamps on their behalf, so the schedule stays
    # where it was until something saves the reminder.
    it "does not start expanding in a new zone the moment the senior edits their profile" do
      reminder = senior.reminders.create!(title: "Pills", category: :medication, rrule: "FREQ=DAILY",
                                          start_time: ActiveSupport::TimeZone[tz].local(2026, 7, 9, 9, 0))
      described_class.expand(reminder)
      before = reminder.occurrences.reload.map { |o| o.scheduled_at.to_i }.sort

      senior.update!(name: "Mum", tz: "America/Chicago")
      described_class.expand(reminder.reload)

      expect(reminder.occurrences.reload.map { |o| o.scheduled_at.to_i }.sort).to eq(before)
    end

    it "does not raise when the stamped zone does not resolve at all" do
      reminder = senior.reminders.create!(title: "Pills", category: :medication,
                                          rrule: "FREQ=DAILY",
                                          start_time: ActiveSupport::TimeZone[tz].local(2026, 7, 9, 8, 39))
      reminder.update_column(:tz, "Neverwhere/Nowhere")

      expect { described_class.expand(reminder.reload) }.not_to raise_error
    end
  end

  # A reminder set up months ago used to be replayed in full on every expansion,
  # to keep the two slots the method actually acts on. Harmless when this ran on
  # a page visit; multiplied by twenty-four once an hourly sweep calls it, and
  # growing by one occurrence a day for as long as the reminder exists.
  describe "a reminder that has been running for months" do
    let(:long_running) do
      senior.reminders.create!(title: "Morning pills", category: :medication, rrule: "FREQ=DAILY",
                               start_time: ActiveSupport::TimeZone[tz].local(2025, 11, 26, 8, 0))
    end

    it "asks IceCube only for the window it can act on" do
      asked = nil
      allow_any_instance_of(IceCube::Schedule).to receive(:occurrences_between).and_wrap_original do |original, from, to, *rest|
        asked = from
        original.call(from, to, *rest)
      end

      described_class.expand(long_running)

      expect(asked.to_date).to eq(Time.current.in_time_zone(tz).to_date)
    end

    # The point of the bound is that it changes nothing about the result.
    it "creates exactly the occurrences it did before, at the same times" do
      described_class.expand(long_running)

      times = long_running.occurrences.reload.map { |o| o.scheduled_at.in_time_zone(tz).strftime("%-l:%M%P") }.uniq
      expect(times).to eq([ "8:00am" ])
    end

    # A reminder whose start_time is still ahead of today must not be enumerated
    # from today either — the later of the two bounds is the one to use.
    it "does not enumerate a reminder that has not started yet" do
      future = senior.reminders.create!(title: "Later", category: :routine, rrule: "FREQ=DAILY",
                                        start_time: ActiveSupport::TimeZone[tz].local(2026, 12, 1, 9, 0))
      asked = nil
      allow_any_instance_of(IceCube::Schedule).to receive(:occurrences_between).and_wrap_original do |original, from, to, *rest|
        asked = from
        original.call(from, to, *rest)
      end

      described_class.expand(future)

      expect(asked.to_date).to eq(Date.new(2026, 12, 1))
    end
  end
end
