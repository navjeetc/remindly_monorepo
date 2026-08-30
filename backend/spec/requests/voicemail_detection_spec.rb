# frozen_string_literal: true

require "rails_helper"

# Reported from a real call: the 16:13 reminder left its script on a voicemail,
# in Spanish, and was recorded no_response. Nothing asked Telnyx to detect a
# machine, and Telnyx fires call.answered for a mailbox exactly as it does for a
# person -- so the prompt played to the mailbox and the reminder title went with
# it.
#
# That title is the part that matters. The privacy policy already warns it is
# "read aloud by the automated phone call, in whatever room the phone happens to
# be in"; a mailbox is further than a room, because it keeps the recording,
# syncs it and hands it to whoever holds the phone. The consent script is worse
# again: nobody can press 1 on a recording, so consent can never complete, and
# an unsolicited anti-scam script sitting in a stranger's voicemail is precisely
# what a scam sounds like.
RSpec.describe "Voicemail detection on reminder calls", type: :request do
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

    # Same as telnyx_webhooks_spec: the controller authenticates the webhook
    # against credentials, so without these every post here is rejected and the
    # examples pass by never reaching the code under test.
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  describe "when a machine picks up" do
    # The title is the whole reason this feature exists. Everything else about a
    # machine verdict is recoverable; a medication name on a mailbox is not.
    it "never says the reminder title" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
      expect(TelnyxVoiceService).not_to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
    end

    it "offers a way through, rather than hanging up" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
      expect(TelnyxVoiceService).not_to have_received(:hangup)
    end

    # "The mailbox took it" and "the phone rang out" are different things to tell
    # a caregiver, and only one of them means the handset was near anybody.
    it "records the outcome as voicemail, not no_response" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")
      telnyx_post("call.hangup")

      expect(telnyx_call.reload.outcome).to eq("voicemail")
    end

    # A machine picking up is still nobody answering, so the flag that exists for
    # doses with a narrow window has to fire on it.
    it "still alerts the caregivers when the reminder is time-critical" do
      reminder.update!(critical: true)
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)

      allow(ReminderNotificationService).to receive(:notify_unanswered)

      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")
      telnyx_post("call.hangup")

      expect(ReminderNotificationService).to have_received(:notify_unanswered)
    end
  end

  describe "when a person picks up" do
    it "speaks the reminder once the verdict says human" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "human")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
      expect(TelnyxVoiceService).not_to have_received(:hangup)
    end

    # Hanging up on somebody who has just said hello is a worse failure than
    # occasionally talking to a mailbox, so only an explicit machine verdict
    # suppresses the prompt.
    it "speaks when detection could not decide" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "not_sure")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
      expect(TelnyxVoiceService).not_to have_received(:hangup)
    end

    it "speaks when the verdict carries no result at all" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
    end

    # Telnyx redelivers, and a second prompt would talk over the first.
    it "does not speak twice when the verdict is redelivered" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "human")
      telnyx_post("call.machine.detection.ended", result: "human")

      expect(TelnyxVoiceService).to have_received(:gather_digit).once
    end
  end

  # Call 39 in production, 22:02:00-22:02:08: Telnyx returned "machine" for a
  # person who had answered and said hello, and the first version of this fix
  # hung up on them. The reminder was simply dropped. Detection will always get
  # this wrong sometimes, so being wrong has to cost a keypress rather than a
  # dose.
  describe "when detection is wrong and a person is there" do
    it "gives them the reminder once they press a key" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")
      telnyx_post("call.gather.ended", digits: "1")

      expect(TelnyxVoiceService).to have_received(:gather_digit).twice
      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
    end

    it "is an ordinary call again afterwards, not a voicemail" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")
      telnyx_post("call.gather.ended", digits: "1")

      expect(telnyx_call.reload.outcome).to eq("pending")
      expect(telnyx_call.answered_at).to be_present
    end

    it "then takes the keypress that acknowledges it" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")
      telnyx_post("call.gather.ended", digits: "1")
      telnyx_post("call.gather.ended", digits: "1")

      expect(occurrence.reload.status).to eq("acknowledged")
    end

    it "never hangs up on them" do
      telnyx_post("call.answered")
      telnyx_post("call.machine.detection.ended", result: "machine")

      expect(TelnyxVoiceService).not_to have_received(:hangup)
    end
  end

  # The regression itself: answering must no longer be enough to make it talk.
  it "does not speak on call.answered alone, which a mailbox also triggers" do
    telnyx_post("call.answered")

    expect(TelnyxVoiceService).not_to have_received(:gather_digit)
    expect(telnyx_call.reload.answered_at).to be_nil
  end

  it "asks Telnyx to detect a machine when it dials" do
    expect(TelnyxVoiceService::API_BASE).to be_present
    payload = nil
    allow(TelnyxVoiceService).to receive(:post) { |_path, body, **| payload = body; { "data" => { "call_control_id" => "x" } } }
    allow(TelnyxVoiceService).to receive(:credentials).and_return(from_number: "+15550000000", connection_id: "conn-1")

    TelnyxVoiceService.dial(occurrence, attempt: telnyx_call)

    expect(payload[:answering_machine_detection]).to eq("detect")
  end

  # The defaults call silence a machine, because silence crosses
  # initial_silence_millis before anything else fires. The people this product
  # rings answer silently often enough that the defaults are the wrong shape:
  # analysis has to run out before initial silence can trip, so a silent pickup
  # comes back not_sure and is spoken to.
  it "sends thresholds that stop silence being read as a machine" do
    payload = nil
    allow(TelnyxVoiceService).to receive(:post) { |_path, body, **| payload = body; { "data" => { "call_control_id" => "x" } } }
    allow(TelnyxVoiceService).to receive(:credentials).and_return(from_number: "+15550000000", connection_id: "conn-1")

    TelnyxVoiceService.dial(occurrence, attempt: telnyx_call)
    config = payload[:answering_machine_detection_config]

    expect(config[:initial_silence_millis]).to be > config[:total_analysis_time_millis]

    # and a mailbox still has to be caught inside the window, or a real
    # voicemail comes back not_sure and gets spoken to as well
    expect(config[:greeting_duration_millis]).to be < config[:total_analysis_time_millis]
  end
end
