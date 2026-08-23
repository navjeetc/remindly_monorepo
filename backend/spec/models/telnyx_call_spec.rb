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

    it "returns nil rather than raising when the slot is already taken" do
      day = described_class.local_day(senior, Time.current)
      described_class.create!(occurrence: occurrence_at(Time.current), user: senior,
                              attempt_number: 1, call_day: day, daily_sequence: 1,
                              status: "initiated", outcome: "pending")

      # A second reserve computing the same next number, as two threads would.
      allow(described_class).to receive(:where).and_call_original
      relation = described_class.where(user_id: senior.id, call_day: day)
      allow(relation).to receive(:maximum).with(:daily_sequence).and_return(0)
      allow(described_class).to receive(:where).with(user_id: senior.id, call_day: day).and_return(relation)

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_nil
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
