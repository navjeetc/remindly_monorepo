require "rails_helper"
require Rails.root.join("db/migrate/20260825030000_keep_reminders_in_the_seniors_clock.rb")

# The repair itself, because what it deletes matters more than what it fixes.
#
# Dropping every pending occurrence would have been the obvious implementation
# and destroys three things it should not: a live snooze (a one-off row expand
# never recreates), the delivery history hanging off an occurrence
# (has_many :telnyx_calls, dependent: :destroy), and its acknowledgements.
RSpec.describe KeepRemindersInTheSeniorsClock do
  let(:eastern) { ActiveSupport::TimeZone["America/New_York"] }
  let(:senior) { create(:user, :senior, name: "Mum", tz: "America/New_York") }

  # The shape this migration exists to repair: stamped with a zone that is not
  # the senior's, which only update_column can produce now that the model
  # forbids it.
  def drifted_reminder
    senior.reminders.create!(title: "Take sleep medicine", category: :medication, rrule: "FREQ=DAILY",
                             start_time: eastern.local(2026, 8, 20, 20, 41))
          .tap { |r| r.update_column(:tz, "New Delhi") }
  end

  before { ActiveRecord::Migration.verbose = false }
  after { ActiveRecord::Migration.verbose = true }

  it "re-stamps the reminder with the senior's clock" do
    reminder = drifted_reminder

    described_class.new.up

    expect(reminder.reload.tz).to eq("America/New_York")
  end

  it "normalises a zone that differs only in spelling, without touching the schedule" do
    reminder = senior.reminders.create!(title: "Pills", category: :medication, rrule: "FREQ=DAILY",
                                        start_time: eastern.local(2026, 8, 20, 9, 0))
    reminder.update_column(:tz, "Eastern Time (US & Canada)")
    Recurrence.expand(reminder.reload)
    before = reminder.occurrences.pluck(:id).sort

    described_class.new.up

    expect(reminder.reload.tz).to eq("America/New_York")
    expect(reminder.occurrences.pluck(:id).sort).to eq(before)
  end

  describe "what it refuses to delete" do
    # snooze! materialises a one-off pending occurrence at the snoozed time.
    # It is not an RRULE slot, so expand would never bring it back — deleting it
    # silently cancels a snooze the senior asked for.
    it "keeps a snoozed occurrence" do
      reminder = drifted_reminder
      due = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 20, 41), status: :pending)
      snoozed = due.snooze!

      described_class.new.up

      expect(Occurrence.exists?(snoozed.id)).to be true
      expect(snoozed.reload.status).to eq("pending")
    end

    # Occurrence has_many :telnyx_calls, dependent: :destroy — so deleting the
    # occurrence takes the record of every call placed about that dose with it.
    it "keeps an occurrence that has call history, and the calls themselves" do
      reminder = drifted_reminder
      occ = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 20, 41), status: :pending)
      call = TelnyxCall.create!(occurrence: occ, user: senior, attempt_number: 1,
                                status: "completed", outcome: "no_response", completed_at: Time.current)

      described_class.new.up

      expect(Occurrence.exists?(occ.id)).to be true
      expect(TelnyxCall.exists?(call.id)).to be true
    end

    it "keeps an occurrence somebody has already acknowledged something about" do
      reminder = drifted_reminder
      occ = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 20, 41), status: :pending)
      Acknowledgement.create!(occurrence: occ, kind: "taken", at: Time.current)

      described_class.new.up

      expect(Occurrence.exists?(occ.id)).to be true
    end
  end

  it "does drop a plain drifted slot, so the senior is not reminded twice an hour apart" do
    reminder = drifted_reminder
    Recurrence.expand(reminder)
    plain = reminder.occurrences.where(status: :pending).first
    expect(plain).to be_present

    described_class.new.up

    expect(Occurrence.exists?(plain.id)).to be false
  end
end
