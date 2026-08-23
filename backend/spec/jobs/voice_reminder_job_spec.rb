require "rails_helper"

# The guard here is the last thing between a person and a ringing telephone, so
# it is tested at this level as well as on the model: this job is reachable
# without the scheduler — a console, a retry hours after the failure that caused
# it — and a call placed at 3am cannot be taken back.
RSpec.describe VoiceReminderJob do
  include ActiveSupport::Testing::TimeHelpers # the project's convention, see recurrence_spec

  let(:senior) { create(:user, :senior, name: "Peter", tz: "America/New_York", phone: "+15551234567", voice_reminders_enabled: true) }
  let(:reminder) { Reminder.create!(user: senior, title: "Take meds", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending) }

  def at(hour)
    ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, hour, 0)
  end

  before { allow(TelnyxVoiceService).to receive(:dial) }

  # The feature is off by default, everywhere. These specs are about what
  # happens once it is on; the two below assert that off means off.
  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
  end

  it "places no call at all while the feature flag is off" do
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
    expect(occurrence.telnyx_calls).to be_empty
  end


  it "dials inside calling hours" do
    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).to have_received(:dial)
      .with(occurrence, attempt: an_instance_of(TelnyxCall))
  end

  # The attempt row has to exist before the provider is called. If it were
  # written afterwards, two runs would both POST before either could see the
  # other, and the senior's phone would ring twice for one dose.
  it "claims the attempt before dialling, so a concurrent run cannot also dial" do
    claimed = nil
    allow(TelnyxVoiceService).to receive(:dial) { |_occ, attempt:| claimed = attempt }

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(claimed).to be_persisted
    expect(claimed.attempt_number).to eq(1)
    expect(claimed.status).to eq("reserved")
  end

  it "does not dial when another run has already claimed this attempt" do
    TelnyxCall.create!(occurrence: occurrence, user: senior, attempt_number: 1,
                       status: "reserved", outcome: "pending")

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  # The bug this replaces: attempts reused one row, so the scheduler's
  # "recently called" window never advanced and an unanswered senior was
  # re-dialled every minute until the missed sweep closed the occurrence -- some
  # fifty-odd calls, all inside legal hours.
  it "stops after the attempt cap, however often the job is run" do
    TelnyxCall::MAX_ATTEMPTS.times do |i|
      travel_to(at(10) + (i * (TelnyxCall::RETRY_AFTER + 1.minute))) do
        described_class.new.perform(occurrence.id)
      end
    end

    # Well past the retry window, and every minute of it — the shape of the
    # scheduler's real cadence.
    20.times do |i|
      travel_to(at(12) + i.minutes) { described_class.new.perform(occurrence.id) }
    end

    expect(TelnyxVoiceService).to have_received(:dial).exactly(TelnyxCall::MAX_ATTEMPTS).times
    expect(occurrence.telnyx_calls.count).to eq(TelnyxCall::MAX_ATTEMPTS)
  end

  it "waits out the retry window before trying again" do
    travel_to(at(10)) { described_class.new.perform(occurrence.id) }
    travel_to(at(10) + TelnyxCall::RETRY_AFTER - 1.minute) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).to have_received(:dial).once
  end

  it "places no call at 3am, whatever the occurrence says it is due" do
    travel_to(at(3)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  it "places no call once the window has closed at 9pm" do
    travel_to(at(21)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  it "places no call when the senior's timezone cannot be resolved" do
    senior.update_column(:tz, "Neverwhere/Nowhere")

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  # The unique index arbitrates between competing callers; it says nothing about
  # the occurrence being resolved meanwhile through the web page.
  it "does not dial when the occurrence is resolved after the attempt is claimed" do
    allow(TelnyxCall).to receive(:reserve).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap { occurrence.update!(status: :acknowledged) }
    end

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
    expect(occurrence.telnyx_calls.last.status).to eq("cancelled")
  end

  it "records why a call was withheld, rather than leaving it to be inferred later" do
    travel_to(at(3)) { described_class.new.perform(occurrence.id) }

    expect(occurrence.reload.call_suppressed_reason).to eq("outside_calling_hours")
    expect(occurrence.call_suppressed_at).to be_present
  end

  it "places no call for an occurrence that is already acknowledged" do
    occurrence.update!(status: :acknowledged)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end
  it "does not dial a senior who has switched voice reminders off since the job was enqueued" do
    senior.update!(voice_reminders_enabled: false)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
    expect(occurrence.telnyx_calls).to be_empty
  end

  it "does not dial a senior whose phone number has been cleared" do
    senior.update!(phone: nil)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  # MAX_ATTEMPTS is per occurrence, so a senior with several reminders due could
  # take three calls each and never exceed it.
  it "stops at the per-senior daily cap however many reminders are due" do
    TelnyxCall::MAX_CALLS_PER_DAY.times do |i|
      other = Occurrence.create!(reminder: reminder, scheduled_at: at(9) + i.minutes, status: :pending)
      TelnyxCall.create!(occurrence: other, user: senior, attempt_number: 1,
                         call_control_id: "spent-#{i}", status: "hangup", outcome: "no_response",
                         created_at: at(9) + i.minutes)
    end

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end

  it "counts that cap in the senior's own day, not the server's" do
    # 23:30 the previous evening in New York is already the next UTC day.
    TelnyxCall::MAX_CALLS_PER_DAY.times do |i|
      other = Occurrence.create!(reminder: reminder, scheduled_at: at(9) + i.minutes, status: :pending)
      TelnyxCall.create!(occurrence: other, user: senior, attempt_number: 1,
                         call_control_id: "yesterday-#{i}", status: "hangup", outcome: "no_response",
                         created_at: at(10) - 1.day)
    end

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).to have_received(:dial)
  end

  # The sweep can close an occurrence while its call is still queued.
  it "records that no call was placed when the sweep closed the occurrence first" do
    occurrence.update!(status: :missed)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(occurrence.reload.call_suppressed_reason).to eq("not_attempted_in_time")
  end

  it "records nothing when the senior resolved it herself" do
    occurrence.update!(status: :acknowledged)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(occurrence.reload.call_suppressed_at).to be_nil
  end
  it "records nothing about calls for a senior who does not take them" do
    senior.update!(voice_reminders_enabled: false)
    occurrence.update!(status: :missed)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(occurrence.reload.call_suppressed_at).to be_nil
  end

  # She resolved it herself between the claim and the dial. Nothing rang, so
  # being prompt with one reminder must not cost her a later one.
  it "does not spend the daily allowance on attempts that were cancelled" do
    (TelnyxCall::MAX_CALLS_PER_DAY + 2).times do |i|
      other = Occurrence.create!(reminder: reminder, scheduled_at: at(9) + i.minutes, status: :acknowledged)
      TelnyxCall.create!(occurrence: other, user: senior, attempt_number: 1,
                         status: "cancelled", outcome: "no_response",
                         created_at: at(9) + i.minutes)
    end

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).to have_received(:dial)
  end
end
