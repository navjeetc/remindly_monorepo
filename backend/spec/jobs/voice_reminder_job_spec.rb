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

  it "dials inside calling hours" do
    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).to have_received(:dial).with(occurrence)
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

  it "places no call for an occurrence that is already acknowledged" do
    occurrence.update!(status: :acknowledged)

    travel_to(at(10)) { described_class.new.perform(occurrence.id) }

    expect(TelnyxVoiceService).not_to have_received(:dial)
  end
end
