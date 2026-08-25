require "rails_helper"
require Rails.root.join("db/migrate/20260825030000_keep_reminders_in_the_seniors_clock.rb")

# The repair itself, because what it deletes matters more than what it fixes.
#
# Dropping every pending occurrence would have been the obvious implementation
# and destroys three things it should not: a live snooze (a one-off row expand
# never recreates), the delivery history hanging off an occurrence
# (has_many :telnyx_calls, dependent: :destroy), and its acknowledgements.
RSpec.describe KeepRemindersInTheSeniorsClock do
  include ActiveSupport::Testing::TimeHelpers

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

    # A slot refused outside calling hours carries a suppression reason and no
    # telnyx_calls at all, so it looked replaceable. Destroying it loses the only
    # evidence that no call was placed, and the caregiver email then says the
    # senior did not mark it done — for a call Remindly itself withheld.
    it "keeps an occurrence whose call was suppressed, and why" do
      reminder = drifted_reminder
      occ = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 20, 41), status: :pending)
      occ.suppress_call!(:outside_calling_hours)

      described_class.new.up

      expect(Occurrence.exists?(occ.id)).to be true
      expect(occ.reload.call_suppressed_reason).to eq("outside_calling_hours")
    end

    # Falling back to the server's zone would compute slots for a schedule this
    # reminder never had, then delete whatever happened to coincide with them.
    it "deletes nothing at all when the stamped zone cannot be resolved" do
      reminder = drifted_reminder
      Recurrence.expand(reminder)
      reminder.update_column(:tz, "Neverwhere/Nowhere")
      before = reminder.occurrences.pluck(:id).sort

      described_class.new.up

      expect(reminder.occurrences.reload.pluck(:id)).to include(*before)
    end

    it "keeps an occurrence somebody has already acknowledged something about" do
      reminder = drifted_reminder
      occ = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 20, 41), status: :pending)
      Acknowledgement.create!(occurrence: occ, kind: "taken", at: Time.current)

      described_class.new.up

      expect(Occurrence.exists?(occ.id)).to be true
    end
  end

  # Preserving a stateful row is only half the job: expansion back-fills the
  # corrected slot for the same day, and the missed sweep then tells the caregiver
  # the senior missed a dose she has already marked done.
  describe "a day that is already settled" do
    it "is not re-opened by the corrected schedule" do
      reminder = drifted_reminder
      travel_to(eastern.local(2026, 8, 21, 22, 0)) do
        done = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 21, 41),
                                  status: :acknowledged)
        Acknowledgement.create!(occurrence: done, kind: "taken", at: Time.current)

        described_class.new.up

        on_that_day = reminder.occurrences.reload.select { |o| o.scheduled_at.in_time_zone(eastern).to_date == Date.new(2026, 8, 21) }
        expect(on_that_day.map(&:id)).to eq([ done.id ])
      end
    end

    it "leaves later days alone, which still need their corrected slot" do
      reminder = drifted_reminder
      travel_to(eastern.local(2026, 8, 21, 22, 0)) do
        done = Occurrence.create!(reminder: reminder, scheduled_at: eastern.local(2026, 8, 21, 21, 41),
                                  status: :acknowledged)
        Acknowledgement.create!(occurrence: done, kind: "taken", at: Time.current)

        described_class.new.up

        later = reminder.occurrences.reload.select { |o| o.scheduled_at.in_time_zone(eastern).to_date > Date.new(2026, 8, 21) }
        expect(later).not_to be_empty
        expect(later.map { |o| o.scheduled_at.in_time_zone(eastern).strftime("%-l:%M%P") }.uniq).to eq([ "8:41pm" ])
      end
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
