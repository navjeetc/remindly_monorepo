require "rails_helper"

RSpec.describe TelnyxCall do
  include ActiveSupport::Testing::TimeHelpers

  let(:senior) { create(:user, :senior, name: "Peter", tz: "America/New_York", phone: "+15551234567") }
  let(:reminder) { Reminder.create!(user: senior, title: "Take meds", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }

  def occurrence_at(moment)
    Occurrence.create!(reminder: reminder, scheduled_at: moment, status: :pending)
  end

  # Two reserves for *different* occurrences cannot be arbitrated by the
  # per-occurrence index, because every occurrence id differs. With three Solid
  # Queue worker threads, three could each read the same count and each insert.
  # The daily slot is what stops them.
  describe "the daily allowance" do
    it "refuses two attempts claiming the same slot in the same local day" do
      day = Date.new(2026, 6, 15)

      described_class.create!(occurrence: occurrence_at(Time.current), user: senior,
                              attempt_number: 1, call_day: day, daily_sequence: 1,
                              status: "initiated", outcome: "pending")

      expect {
        described_class.create!(occurrence: occurrence_at(Time.current + 1.hour), user: senior,
                                attempt_number: 1, call_day: day, daily_sequence: 1,
                                status: "initiated", outcome: "pending")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same slot number on a different day" do
      described_class.create!(occurrence: occurrence_at(Time.current), user: senior,
                              attempt_number: 1, call_day: Date.new(2026, 6, 15), daily_sequence: 1,
                              status: "initiated", outcome: "pending")

      expect {
        described_class.create!(occurrence: occurrence_at(Time.current + 1.day), user: senior,
                                attempt_number: 1, call_day: Date.new(2026, 6, 16), daily_sequence: 1,
                                status: "initiated", outcome: "pending")
      }.not_to raise_error
    end

    it "returns nil rather than raising when the slot is taken between choosing and inserting" do
      day = described_class.local_day(senior, Time.current)

      # Exactly the interleaving two workers produce: both pick the same lowest
      # free slot, and the other one lands first.
      allow(described_class).to receive(:free_slot).and_wrap_original do |original, *args|
        original.call(*args).tap do
          described_class.create!(occurrence: occurrence_at(Time.current + 2.hours), user: senior,
                                  attempt_number: 1, call_day: day, daily_sequence: 1,
                                  status: "initiated", outcome: "pending")
        end
      end

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_nil
    end

    it "hands out every slot in the day and then stops" do
      day = described_class.local_day(senior, Time.current)

      granted = (described_class::MAX_CALLS_PER_DAY + 3).times.map do |i|
        described_class.reserve(occurrence_at(Time.current + i.hours), senior)
      end.compact

      expect(granted.size).to eq(described_class::MAX_CALLS_PER_DAY)
      expect(granted.map(&:daily_sequence).sort).to eq((1..described_class::MAX_CALLS_PER_DAY).to_a)
      expect(described_class.free_slot(senior, day)).to be_nil
    end

    it "reuses a slot released by an attempt that never rang" do
      day = described_class.local_day(senior, Time.current)
      described_class::MAX_CALLS_PER_DAY.times { |i| described_class.reserve(occurrence_at(Time.current + i.hours), senior) }

      expect(described_class.reserve(occurrence_at(Time.current + 20.hours), senior)).to be_nil

      described_class.where(user_id: senior.id, call_day: day, daily_sequence: 4)
                     .first.release_slot!(status: "failed", outcome: "error")

      revived = described_class.reserve(occurrence_at(Time.current + 21.hours), senior)
      expect(revived.daily_sequence).to eq(4)
    end
  end

  # users.tz is mutable, so the calendar day the slots hang off can move under
  # the senior. At 00:30 UTC, Tokyo and Los Angeles are on different dates.
  it "does not hand back a fresh day's slots when the senior changes timezone" do
    travel_to(Time.utc(2026, 6, 24, 0, 30)) do
      senior.update!(tz: "Asia/Tokyo")
      described_class::MAX_CALLS_PER_DAY.times { |i| described_class.reserve(occurrence_at(Time.current + i.hours), senior) }

      expect(described_class.reserve(occurrence_at(Time.current + 20.hours), senior)).to be_nil

      senior.update!(tz: "America/Los_Angeles")

      expect(described_class.reserve(occurrence_at(Time.current + 21.hours), senior)).to be_nil
    end
  end

  it "still allows a normal morning call after a full evening the day before" do
    # The blunt version of the timezone backstop — any call in the last 24 hours
    # — refused this, which is ordinary scheduling rather than an anomaly.
    travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 20, 0)) do
      described_class::MAX_CALLS_PER_DAY.times { |i| described_class.reserve(occurrence_at(Time.current + i.minutes), senior) }
    end

    travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 16, 8, 0)) do
      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
    end
  end

  describe ".local_day" do
    it "uses the senior's zone, not the server's" do
      # 20:00 in New York on the 15th is 00:00 UTC on the 16th.
      moment = ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 20, 0)

      expect(described_class.local_day(senior, moment)).to eq(Date.new(2026, 6, 15))
    end

    it "falls back to the app zone when the senior's cannot be resolved" do
      senior.update_column(:tz, "Neverwhere/Nowhere")

      expect { described_class.local_day(senior, Time.current) }.not_to raise_error
    end
  end
end
