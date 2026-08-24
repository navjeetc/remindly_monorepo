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
                              status: "hangup", outcome: "no_response", completed_at: Time.current)

      expect {
        described_class.create!(occurrence: occurrence_at(Time.current + 1.hour), user: senior,
                                attempt_number: 1, call_day: day, daily_sequence: 1,
                                status: "hangup", outcome: "no_response", completed_at: Time.current)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows the same slot number on a different day" do
      described_class.create!(occurrence: occurrence_at(Time.current), user: senior,
                              attempt_number: 1, call_day: Date.new(2026, 6, 15), daily_sequence: 1,
                              status: "hangup", outcome: "no_response", completed_at: Time.current)

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
          &.tap { |c| c.update!(completed_at: Time.current) } # the call ends before the next begins
      end.compact

      expect(granted.size).to eq(described_class::MAX_CALLS_PER_DAY)
      expect(granted.map(&:daily_sequence).sort).to eq((1..described_class::MAX_CALLS_PER_DAY).to_a)
      expect(described_class.free_slot(senior, day)).to be_nil
    end

    it "reuses a slot released by an attempt that never rang" do
      day = described_class.local_day(senior, Time.current)
      described_class::MAX_CALLS_PER_DAY.times do |i|
        described_class.reserve(occurrence_at(Time.current + i.hours), senior)&.update!(completed_at: Time.current)
      end

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
      described_class::MAX_CALLS_PER_DAY.times do |i|
        described_class.reserve(occurrence_at(Time.current + i.hours), senior)&.update!(completed_at: Time.current)
      end

      expect(described_class.reserve(occurrence_at(Time.current + 20.hours), senior)).to be_nil

      senior.update!(tz: "America/Los_Angeles")

      expect(described_class.reserve(occurrence_at(Time.current + 21.hours), senior)).to be_nil
    end
  end

  it "still allows a normal morning call after a full evening the day before" do
    # The blunt version of the timezone backstop — any call in the last 24 hours
    # — refused this, which is ordinary scheduling rather than an anomaly.
    travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 20, 0)) do
      described_class::MAX_CALLS_PER_DAY.times do |i|
        described_class.reserve(occurrence_at(Time.current + i.minutes), senior)&.update!(completed_at: Time.current)
      end
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
  # Found live: a dose falling due at the same moment as another occurrence's
  # retry dialled the same phone twice in the same second. One was answered and
  # the other talked to voicemail, having spent a daily slot on a call nobody
  # could pick up.
  describe "one call at a time" do
    it "refuses a second reservation while a call is still in progress" do
      first = described_class.reserve(occurrence_at(Time.current), senior)
      expect(first).to be_present

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_nil
    end

    it "allows the next one once the call has finished" do
      described_class.reserve(occurrence_at(Time.current), senior).update!(completed_at: Time.current)

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_present
    end

    it "is not blocked by an attempt that never rang" do
      described_class.reserve(occurrence_at(Time.current), senior)
                     .release_slot!(status: "failed", outcome: "error")

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_present
    end

    # A row abandoned by a dead worker must not hold the line for the rest of
    # the day.
    it "stops believing an unfinished attempt after the in-flight window" do
      described_class.reserve(occurrence_at(Time.current), senior)
                     .update!(created_at: described_class::IN_FLIGHT_WINDOW.ago - 1.minute)

      expect(described_class.reserve(occurrence_at(Time.current + 1.hour), senior)).to be_present
    end

    it "does not block a different senior" do
      other = create(:user, :senior, name: "Mary", tz: "America/New_York", phone: "+15559998888")
      other_reminder = Reminder.create!(user: other, title: "Take meds", category: :medication, rrule: "FREQ=DAILY", tz: other.tz)
      described_class.reserve(occurrence_at(Time.current), senior)

      theirs = Occurrence.create!(reminder: other_reminder, scheduled_at: Time.current, status: :pending)
      expect(described_class.reserve(theirs, other)).to be_present
    end
  end
  # A verification call asks whether this number consents to be telephoned. It
  # belongs to a number rather than to a dose, so it has no occurrence and holds
  # no reminder slot — which is exactly why its own bounds have to be explicit.
  describe "verification calls" do
    # Verification calls are refused outside the senior's calling window, so
    # without a fixed clock these pass by day and fail by night.
    around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

    before { senior.update!(phone: "+15551234567") }

    it "is claimed without an occurrence" do
      call = described_class.reserve_verification(senior)

      expect(call.purpose).to eq("verification")
      expect(call.occurrence_id).to be_nil
      expect(call.daily_sequence).to be_nil
    end

    it "refuses to exist as a reminder without an occurrence" do
      call = described_class.new(user: senior, purpose: "reminder", attempt_number: 1,
                                 status: "reserved", outcome: "pending")

      expect(call).not_to be_valid
      expect(call.errors[:occurrence]).to be_present
    end

    it "refuses to claim an occurrence, since it announces no dose" do
      call = described_class.new(user: senior, purpose: "verification", attempt_number: 1,
                                 occurrence: occurrence_at(Time.current),
                                 status: "reserved", outcome: "pending")

      expect(call).not_to be_valid
    end

    # Counted, then created, with nothing behind it: two caregivers or one
    # double-click could both read the same count and both insert. The rescue
    # for RecordNotUnique had nothing that could raise it.
    it "refuses a second claim on the same attempt number" do
      first = described_class.reserve_verification(senior)

      duplicate = described_class.new(user: senior, purpose: "verification",
                                      attempt_number: first.attempt_number,
                                      call_day: first.call_day,
                                      to_number: first.to_number,
                                      status: "reserved", outcome: "pending")

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "records the number it is about to dial, so consent can be checked against it" do
      call = described_class.reserve_verification(senior)

      expect(call.to_number).to eq(senior.phone)
    end

    it "records who asked for it, because the call says their name aloud" do
      asker = create(:user, :caregiver, name: "Jane", email: "asker@example.com")

      call = described_class.reserve_verification(senior, requested_by: asker)

      expect(call.requested_by).to eq(asker)
    end

    it "stops after five in one day" do
      granted = 7.times.map do
        described_class.reserve_verification(senior)&.tap { |c| c.update!(completed_at: Time.current) }
      end.compact

      expect(granted.size).to eq(described_class::MAX_VERIFICATIONS_PER_DAY)
    end

    it "does not spend a reminder slot" do
      described_class.reserve_verification(senior).update!(completed_at: Time.current)

      expect(described_class.free_slot(senior, described_class.local_day(senior, Time.current))).to eq(1)
    end

    # The rule that matters most, and the one an earlier version exempted them
    # from: a verification call and a reminder call must never ring one phone at
    # the same moment.
    it "blocks a reminder call while it is live" do
      described_class.reserve_verification(senior)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_nil
    end

    it "is blocked by a live reminder call" do
      described_class.reserve(occurrence_at(Time.current), senior)

      expect(described_class.reserve_verification(senior)).to be_nil
    end

    it "does not block once it has ended" do
      described_class.reserve_verification(senior).update!(completed_at: Time.current)

      expect(described_class.reserve_verification(senior)).to be_present
    end

    it "is refused for a user with no number to verify" do
      senior.update!(phone: nil)

      expect(described_class.reserve_verification(senior)).to be_nil
    end
  end
  # call_in_flight? is a read, so two reservations can both see an idle line
  # before either writes. A verification racing a reminder collides on no other
  # index — verification holds no daily_sequence and has no occurrence — so the
  # partial unique index on user_id is what actually decides.
  describe "one live call per senior, enforced" do
    # Verification calls are refused outside the senior's calling window, so
    # without a fixed clock these pass by day and fail by night.
    around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

    before { senior.update!(phone: "+15551234567") }

    it "refuses a second live call however it is claimed" do
      described_class.reserve_verification(senior)

      expect {
        described_class.create!(occurrence: occurrence_at(Time.current), user: senior,
                                attempt_number: 1, to_number: senior.phone,
                                status: "reserved", outcome: "pending")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # users.phone is not unique. Two accounts can hold one handset — a couple
    # sharing a landline, or a duplicate record — and it is the telephone that
    # can only take one call, not the account.
    it "refuses a call to a number another account is already calling" do
      described_class.reserve_verification(senior)

      housemate = create(:user, :senior, name: "Dad", tz: senior.tz, phone: senior.phone)
      other_reminder = Reminder.create!(user: housemate, title: "Take meds", category: :medication,
                                        rrule: "FREQ=DAILY", tz: housemate.tz)
      theirs = Occurrence.create!(reminder: other_reminder, scheduled_at: Time.current, status: :pending)

      expect(described_class.reserve(theirs, housemate)).to be_nil
    end

    it "does not block a different number on the same account" do
      described_class.reserve_verification(senior).update!(completed_at: Time.current)
      senior.update!(phone: "+15557776666")

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
    end

    it "allows the next one once the first has ended" do
      described_class.reserve_verification(senior).update!(completed_at: Time.current)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
    end

    # The index cannot be told a row is merely old, so something has to close
    # one whose worker died — otherwise a senior's line is held for ever.
    it "closes an attempt abandoned past the in-flight window and lets the next through" do
      stale = described_class.reserve_verification(senior)
      stale.update_columns(created_at: described_class::IN_FLIGHT_WINDOW.ago - 1.minute)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
      expect(stale.reload.completed_at).to be_present
      expect(stale.outcome).to eq("error")
    end

    it "does not close an attempt that is merely in progress" do
      live = described_class.reserve_verification(senior)

      described_class.reserve(occurrence_at(Time.current), senior)

      expect(live.reload.completed_at).to be_nil
    end
  end
  # A verification call rings a real telephone, so the window protecting every
  # reminder call protects this one too. Nothing else enforced it.
  describe "verification calls and the calling window" do
    before { senior.update!(phone: "+15551234567") }

    it "refuses to ring somebody at three in the morning" do
      travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 3, 0)) do
        expect(described_class.reserve_verification(senior)).to be_nil
      end
    end

    it "allows it inside the window" do
      travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) do
        expect(described_class.reserve_verification(senior)).to be_present
      end
    end
  end

  # users.phone is not unique, so two records sharing a landline would otherwise
  # carry five attempts each and ring one handset ten times.
  it "counts the verification allowance against the number, not the account" do
    senior.update!(phone: "+15551234567")
    housemate = create(:user, :senior, name: "Dad", tz: senior.tz, phone: senior.phone)

    described_class::MAX_VERIFICATIONS_PER_DAY.times do
      described_class.reserve_verification(senior)&.update!(completed_at: Time.current)
    end

    expect(described_class.reserve_verification(housemate)).to be_nil
  end

  # The live-call claim is a unique index, so a hangup webhook that never
  # arrives would make a number permanently uncallable. Age alone cannot settle
  # it — a long call is just long — so the provider is asked.
  describe "reconciling a dialled call whose hangup never arrived" do
    # Verification calls are refused outside the senior's calling window, so
    # without a fixed clock these pass by day and fail by night.
    around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

    before { senior.update!(phone: "+15551234567") }

    def stale_dialled_call
      described_class.reserve_verification(senior).tap do |c|
        c.update!(call_control_id: "v3:dialled")
        c.update_columns(created_at: described_class::IN_FLIGHT_WINDOW.ago - 1.minute)
      end
    end

    it "closes the claim when the provider says the call has ended" do
      call = stale_dialled_call
      allow(TelnyxVoiceService).to receive(:alive?).and_return(false)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
      expect(call.reload.completed_at).to be_present
    end

    it "leaves it alone while the provider says it is still connected" do
      call = stale_dialled_call
      allow(TelnyxVoiceService).to receive(:alive?).and_return(true)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_nil
      expect(call.reload.completed_at).to be_nil
    end

    # Closing on a failed lookup would free the line while somebody was still
    # talking on it.
    it "waits rather than guessing when the provider cannot be reached" do
      call = stale_dialled_call
      allow(TelnyxVoiceService).to receive(:alive?).and_return(nil)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_nil
      expect(call.reload.completed_at).to be_nil
    end

    # ...but not for ever. No reminder call lasts an hour.
    it "gives up waiting after an hour, so a lost webhook cannot disable a number" do
      call = stale_dialled_call
      call.update_columns(created_at: described_class::ABANDONED_AFTER.ago - 1.minute)
      allow(TelnyxVoiceService).to receive(:alive?).and_return(nil)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_present
      expect(call.reload.completed_at).to be_present
    end
  end
  # Follow-ups to the reconciliation fix itself.
  describe "reconciliation edge cases" do
    around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }
    before { senior.update!(phone: "+15551234567") }

    def stale_dialled_call(age:)
      described_class.reserve_verification(senior).tap do |c|
        c.update!(call_control_id: "v3:dialled")
        c.update_columns(created_at: age.ago)
      end
    end

    # The clock must not override the provider. A call an hour old is broken,
    # but it is broken and connected, and releasing the claim would put a second
    # call on a line somebody is still holding.
    it "hangs up an hour-old call the provider says is still connected, rather than abandoning it" do
      call = stale_dialled_call(age: described_class::ABANDONED_AFTER + 1.minute)
      allow(TelnyxVoiceService).to receive(:alive?).and_return(true, false)
      allow(TelnyxVoiceService).to receive(:hangup)

      described_class.reserve(occurrence_at(Time.current), senior)

      expect(TelnyxVoiceService).to have_received(:hangup).with(call_control_id: "v3:dialled")
      expect(call.reload.completed_at).to be_present
    end

    it "keeps the claim when the hangup does not take" do
      call = stale_dialled_call(age: described_class::ABANDONED_AFTER + 1.minute)
      allow(TelnyxVoiceService).to receive(:alive?).and_return(true)
      allow(TelnyxVoiceService).to receive(:hangup)

      expect(described_class.reserve(occurrence_at(Time.current), senior)).to be_nil
      expect(call.reload.completed_at).to be_nil
    end
  end

  # users.tz is editable, so a day derived from it can be reset. The reminder cap
  # uses the local day deliberately; this bound must not be resettable.
  it "counts a verification day in UTC, so a timezone change cannot refill the allowance" do
    travel_to(Time.utc(2026, 6, 24, 12, 0)) do
      senior.update!(phone: "+15551234567", tz: "America/New_York")
      described_class::MAX_VERIFICATIONS_PER_DAY.times do
        described_class.reserve_verification(senior)&.update!(completed_at: Time.current)
      end

      senior.update!(tz: "Asia/Tokyo")

      expect(described_class.reserve_verification(senior)).to be_nil
    end
  end
end
