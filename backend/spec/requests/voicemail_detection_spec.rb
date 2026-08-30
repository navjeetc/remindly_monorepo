# frozen_string_literal: true

require "rails_helper"

# A reminder call opens with a line carrying no title, and the title is spoken
# only once somebody presses a key.
#
# This began as answering-machine detection and that approach was abandoned on
# evidence. Four live calls: a person answering silently was called a machine
# twice, and the actual voicemail was called not-a-machine twice -- on provider
# defaults and on tuned thresholds alike. The verdict was wrong in the direction
# that mattered, and a reminder title reached a mailbox both times a real
# mailbox picked up.
#
# A mailbox cannot press a key. That is the whole guarantee, and it does not
# depend on anybody's classifier being right.
RSpec.describe "Reminder calls never speak the title unprompted", type: :request do
  let(:senior) { create(:user, :senior, phone: "+15551234567", call_reminders_enabled: true) }
  let(:caregiver) { create(:user, :caregiver, name: "Janey") }
  let(:reminder) { Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending) }
  let(:telnyx_call) do
    TelnyxCall.create!(call_control_id: "call-123", call_leg_id: "leg-123", occurrence: occurrence,
                       user: senior, status: "initiated", outcome: "pending")
  end

  def telnyx_post(event_type, payload = {})
    post "/telnyx/webhooks",
      params: { token: "test-token",
                data: { event_type: event_type,
                        payload: payload.merge(call_control_id: telnyx_call.call_control_id) } }
  end

  before do
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)

    # Without these the controller rejects every post and the examples pass by
    # never reaching the code under test.
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  # The one that matters. Everything a mailbox can record, it records from this
  # first prompt, because nothing else is said until a key is pressed.
  describe "what a mailbox can record" do
    it "never contains the reminder title" do
      telnyx_post("call.answered")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
      expect(TelnyxVoiceService).not_to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
    end

    it "names Remindly, so the recording is not an anonymous robocall" do
      telnyx_post("call.answered")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Remindly")))
    end

    it "stays silent after the opening line when nobody presses anything" do
      telnyx_post("call.answered")
      telnyx_post("call.hangup")

      expect(TelnyxVoiceService).to have_received(:gather_digit).once
      expect(telnyx_call.reload.answered_at).to be_nil
      expect(telnyx_call.outcome).to eq("no_response")
    end
  end

  describe "when a person presses a key" do
    it "then speaks the reminder they were rung about" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", digits: "1")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
    end

    it "takes the keypress that acknowledges it, as an ordinary call" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", digits: "1")
      telnyx_post("call.gather.ended", digits: "1")

      expect(occurrence.reload.status).to eq("acknowledged")
      expect(telnyx_call.reload.outcome).to eq("taken")
    end

    # Any key, not just 1: somebody who presses whatever their thumb finds has
    # still proved they are a person, and refusing them would be perverse.
    it "accepts any key as proof there is somebody there" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", digits: "5")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
    end
  end

  # A machine picking up is still nobody answering, and the flag exists for
  # doses with a narrow window.
  it "alerts the caregivers when a time-critical reminder goes unanswered" do
    reminder.update!(critical: true)
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    allow(ReminderNotificationService).to receive(:notify_unanswered)

    telnyx_post("call.answered")
    telnyx_post("call.hangup")

    expect(ReminderNotificationService).to have_received(:notify_unanswered)
  end

  it "asks the provider for no machine detection at all" do
    payload = nil
    allow(TelnyxVoiceService).to receive(:post) { |_path, body, **| payload = body; { "data" => { "call_control_id" => "x" } } }
    allow(TelnyxVoiceService).to receive(:credentials).and_return(from_number: "+15550000000", connection_id: "conn-1")

    TelnyxVoiceService.dial(occurrence, attempt: telnyx_call)

    expect(payload).not_to have_key(:answering_machine_detection)
    expect(payload).not_to have_key(:answering_machine_detection_config)
  end
end
