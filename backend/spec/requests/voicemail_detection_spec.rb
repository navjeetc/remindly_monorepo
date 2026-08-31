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

  # event_id is positional, not a keyword: with a keyword here Ruby reads the
  # bare `digits: "1"` at every other call site as keywords rather than as the
  # payload hash.
  def telnyx_post(event_type, payload = {}, event_id = nil)
    data = { event_type: event_type,
             payload: payload.merge(call_control_id: telnyx_call.call_control_id) }
    data[:id] = event_id if event_id

    post "/telnyx/webhooks", params: { token: "test-token", data: data }
  end

  before do
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)
    allow(TelnyxVoiceService).to receive(:hangup!)

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

    # The other half of the same promise. A recording holding "Nora" is not as
    # bad as one holding a medication name, but it still identifies the person
    # to anyone who picks up the phone, and the opening line has no need of it:
    # the reminder itself greets them by name, after a keypress.
    it "never contains the care receiver's name" do
      telnyx_post("call.answered")

      expect(senior.display_name).to be_present
      expect(TelnyxVoiceService).not_to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including(senior.display_name)))
    end

    # The pause is in the synthesised audio, not in our timing: we answer and
    # start speaking within milliseconds, which talks over the "hello" somebody
    # has just started saying. Reported from a live call.
    it "opens with a pause, so it does not talk over the person answering" do
      telnyx_post("call.answered")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(payload_type: "ssml", prompt: a_string_including("<break time=")))
    end

    it "names Remindly, so the recording is not an anonymous robocall" do
      telnyx_post("call.answered")

      expect(TelnyxVoiceService).to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Remindly")))
    end

    # The sequence a real mailbox produces, and the one the first version of this
    # spec skipped: Telnyx sends call.gather.ended when the gather times out,
    # carrying no digits key at all. Posting hangup directly hid that, and the
    # code read the bare event as a keypress and spoke the title onto a
    # voicemail on the first live test.
    it "stays silent when the gather times out with nobody pressing anything" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended")
      telnyx_post("call.hangup")

      expect(TelnyxVoiceService).to have_received(:gather_digit).once
      expect(TelnyxVoiceService).not_to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
      expect(telnyx_call.reload.answered_at).to be_nil
      expect(telnyx_call.outcome).to eq("no_response")
    end

    # Saying nothing is not the same as going away. The first version returned
    # without hanging up, and since the gather was already finished nothing else
    # ended the call -- it sat there recording silence onto the voicemail for as
    # long as the carrier allowed.
    it "hangs up instead of holding the line open recording silence" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended")

      expect(TelnyxVoiceService).to have_received(:hangup!)
        .with(hash_including(call_control_id: "call-123"))
    end

    # Telnyx reports a gather that ended because the caller hung up, and the
    # call is gone by then. Hanging it up again fails, and since this path uses
    # the raising hangup that failure would answer 500, have the event
    # redelivered, and fail again identically -- a loop, out of somebody simply
    # putting the phone down.
    it "does not chase a call the person has already hung up on" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", status: "call_hangup")

      expect(TelnyxVoiceService).not_to have_received(:hangup!)
      expect(response).to have_http_status(:ok)
    end

    # The tolerant hangup logs and returns nil, which would mean a 200 back to
    # Telnyx, no redelivery, and the line left open -- the exact failure this
    # path exists to prevent. It has to be the raising one, so the webhook stays
    # retryable when the hangup does not land.
    it "asks for a retry when the hangup itself fails" do
      allow(TelnyxVoiceService).to receive(:hangup!).and_raise("Telnyx hangup failed")

      telnyx_post("call.answered")
      telnyx_post("call.gather.ended")

      expect(response).to have_http_status(:internal_server_error)
    end

    # Belt and braces: an empty string is not somebody pressing a key either.
    it "stays silent when the gather reports empty digits" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", digits: "")

      expect(TelnyxVoiceService).not_to have_received(:gather_digit)
        .with(hash_including(prompt: a_string_including("Metformin")))
      expect(telnyx_call.reload.answered_at).to be_nil
    end
  end

  # Telnyx redelivers an event when it does not get a 2xx -- including when our
  # 200 was sent but never arrived. The screening keypress and the
  # acknowledgement keypress are both call.gather.ended carrying "1", so a
  # redelivery of the first has to be recognised rather than read as the second.
  describe "when the screening keypress is delivered twice" do
    it "does not mark the dose taken while the reminder is still playing" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", { digits: "1" }, "evt-screening")
      telnyx_post("call.gather.ended", { digits: "1" }, "evt-screening")

      expect(occurrence.reload.status).not_to eq("acknowledged")
      expect(telnyx_call.reload.outcome).to eq("pending")
    end

    it "still accepts the real acknowledgement afterwards" do
      telnyx_post("call.answered")
      telnyx_post("call.gather.ended", { digits: "1" }, "evt-screening")
      telnyx_post("call.gather.ended", { digits: "1" }, "evt-screening")
      telnyx_post("call.gather.ended", { digits: "1" }, "evt-acknowledgement")

      expect(occurrence.reload.status).to eq("acknowledged")
      expect(telnyx_call.reload.outcome).to eq("taken")
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
