# frozen_string_literal: true

require "rails_helper"

# Every call used to end the instant a key was pressed. The keypress was
# recorded, the line went dead, and from the other end that is what a dropped
# call sounds like -- at the exact moment somebody has done the one thing the
# call asked of them.
#
# Reported from a live setup call: "after pressing 1, system just hangs up:
# should say 'Thank you, you're all set'". The daily reminder did the same thing,
# on every call, to the same person.
RSpec.describe "What a call says before it ends", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567", tz: "America/New_York", call_reminders_enabled: true) }
  let(:caregiver) { create(:user, :caregiver, name: "Jane", nickname: "Janey", email: "kid@example.com") }

  def telnyx_post(event_type, call, payload = {})
    post "/telnyx/webhooks",
      params: {
        token: "test-token",
        data: {
          event_type: event_type,
          payload: payload.merge(call_control_id: call.call_control_id)
        }
      }
  end

  before do
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)
    # The farewell's own hangup is the raising one: this event is the only thing
    # that will end the call, so a swallowed failure would answer 200, stop the
    # redelivery and leave somebody connected in silence.
    allow(TelnyxVoiceService).to receive(:hangup!)
    # A real command id comes back when the provider accepts the speak. Nil is
    # the refusal case, and it has its own example below.
    allow(TelnyxVoiceService).to receive(:speak).and_return({ "data" => { "result" => "ok" } })

    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  describe "the verification call" do
    let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver) }
    let(:call) do
      TelnyxCall.reserve_verification(senior, requested_by: caregiver)
                .tap { |c| c.update!(call_control_id: "verify-1") }
    end

    before { telnyx_post("call.answered", call) }

    it "thanks somebody who agrees, and says what happens next" do
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:speak)
        .with(hash_including(message: /Thank you\. You are all set/))
    end

    it "says the calls have stopped when somebody refuses" do
      telnyx_post("call.gather.ended", call, digits: "9")

      expect(TelnyxVoiceService).to have_received(:speak)
        .with(hash_including(message: /We will not call you again/))
    end

    # The whole point. Hanging up in the same breath as the speak command cuts
    # the audio off mid-word, because the hangup does not wait for queued speech.
    it "holds the line open until the farewell has been spoken" do
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).not_to have_received(:hangup)
      expect(TelnyxVoiceService).not_to have_received(:hangup!)

      telnyx_post("call.speak.ended", call)

      expect(TelnyxVoiceService).to have_received(:hangup!)
    end

    # Silence is not a refusal and not an agreement. There is nothing to thank
    # them for and nothing they need to know, so the call simply ends.
    it "says nothing to somebody who pressed nothing" do
      telnyx_post("call.gather.ended", call, digits: "")

      expect(TelnyxVoiceService).not_to have_received(:speak)
        .with(hash_including(message: /Thank you/))
      # The raising hangup: with no farewell playing this is the only thing left
      # to close the line, so a failure must answer 500 and be redelivered.
      expect(TelnyxVoiceService).to have_received(:hangup!)
    end

    # speak answers nil when the provider refuses. The call must still end --
    # the worst case is the abrupt ending this replaces, never a line left open
    # on somebody's telephone.
    it "still hangs up when the provider refuses to speak" do
      allow(TelnyxVoiceService).to receive(:speak).and_return(nil)

      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:hangup!)
    end

    # The outcome settles before a word is spoken, so every speak.ended that
    # follows it looked like the farewell's. A prompt still speaking when
    # somebody pressed a key would then end its own call and cut off the
    # goodbye. Today's prompts use gather_using_speak, which emits no speak
    # events -- this keeps the case shut if that ever changes.
    it "hangs up for the farewell's own speech, not for any speech" do
      telnyx_post("call.gather.ended", call, digits: "1")
      telnyx_post("call.speak.started", call, speak_id: "farewell-speech")

      telnyx_post("call.speak.ended", call, speak_id: "some-other-speech")

      expect(TelnyxVoiceService).not_to have_received(:hangup!)

      telnyx_post("call.speak.ended", call, speak_id: "farewell-speech")

      expect(TelnyxVoiceService).to have_received(:hangup!)
    end

    # Two deliveries of speak.started could both find the column empty, and the
    # loser overwriting the winner would leave the farewell that is actually
    # playing unrecognised -- so nothing would hang up.
    it "keeps the first farewell speech it was told about" do
      telnyx_post("call.gather.ended", call, digits: "1")
      telnyx_post("call.speak.started", call, speak_id: "first")
      telnyx_post("call.speak.started", call, speak_id: "second")

      expect(call.reload.farewell_speak_id).to eq("first")
    end

    # A speech we never saw start is not ours, and holding the line for it would
    # leave somebody connected to silence.
    it "still ends a call whose farewell speech was never seen to start" do
      telnyx_post("call.gather.ended", call, digits: "1")

      telnyx_post("call.speak.ended", call)

      expect(TelnyxVoiceService).to have_received(:hangup!)
    end

    # completed_at is the live-call claim: call_in_flight? and the unique index
    # both read it. Stamping it before the farewell has played would free the
    # handset while somebody is still listening, and the scheduler could dial a
    # second reminder into the same call.
    it "keeps holding the line while the farewell plays" do
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(call.reload.completed_at).to be_nil
      expect(TelnyxCall.call_in_flight?(senior.reload, Time.current)).to be(true)

      telnyx_post("call.hangup", call)

      expect(call.reload.completed_at).to be_present
    end

    # The review case this spec set missed. speak used to end on
    # Rails.logger.error, which answers true, so a timed-out command reported a
    # speech that never left the process -- the line was then held open for a
    # call.speak.ended that could never arrive. Stubbing the raise rather than
    # the return value, because the return value was the bug.
    it "hangs up when the speak command never reaches the provider" do
      allow(TelnyxVoiceService).to receive(:speak).and_call_original
      allow(TelnyxVoiceService).to receive(:post).and_raise(Net::ReadTimeout)

      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:hangup!)
      expect(call.reload.completed_at).to be_present
    end

    # Somebody can press 1 and put the phone down before this event is
    # delivered. Speaking to a call that has gone posts a farewell nothing will
    # hear, and clears the claim on their number for an event that can never
    # come.
    it "says nothing to a call that has already hung up" do
      telnyx_post("call.gather.ended", call, digits: "1", status: "call_hangup")

      expect(TelnyxVoiceService).not_to have_received(:speak)
      expect(call.reload.completed_at).to be_present
    end

    # call.gather.ended and call.hangup can be in flight together, and Puma
    # serves them concurrently. The hangup has to win: nothing else is coming to
    # stamp the row, and a cleared completed_at would claim the line until
    # reconciliation noticed.
    it "does not un-complete a call the hangup has already finished" do
      telnyx_post("call.hangup", call)
      completed = call.reload.completed_at
      expect(completed).to be_present

      telnyx_post("call.gather.ended", call, digits: "1")

      expect(call.reload.completed_at).to eq(completed)
    end

    # Telnyx does not serialise deliveries. A late call.gather.ended arriving
    # after call.hangup used to overwrite the terminal status, so the farewell
    # would speak to a call that had gone and re-claim a number that was free.
    it "does not speak to, or re-claim, a call that has already hung up" do
      telnyx_post("call.hangup", call)
      completed = call.reload.completed_at

      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).not_to have_received(:speak)
      expect(call.reload.status).to eq("hangup")
      expect(call.reload.completed_at).to eq(completed)
    end

    it "records the consent either way" do
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(senior.reload).to be_callable_by_phone
    end
  end

  describe "the daily reminder call" do
    let(:reminder) { Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
    let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending) }
    let(:call) do
      TelnyxCall.create!(call_control_id: "call-123", call_leg_id: "leg-123", occurrence: occurrence,
                         user: senior, status: "initiated", outcome: "pending")
    end

    # Two events: the pickup, then the keypress that gets past the opening line.
    before do
      telnyx_post("call.answered", call)
      telnyx_post("call.gather.ended", call, digits: "1")
    end

    it "says the dose was marked done" do
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:speak)
        .with(hash_including(message: /marked that done/))
      expect(occurrence.reload.status).to eq("acknowledged")
    end

    it "says when it will call back after a snooze" do
      telnyx_post("call.gather.ended", call, digits: "2")

      expect(TelnyxVoiceService).to have_received(:speak)
        .with(hash_including(message: /call you again in #{Occurrence::SNOOZE_DEFAULT_MINUTES} minutes/))
    end

    # The guard that keeps this from being a disaster. The opening line and the
    # reminder itself are speech too, and a bare "speech ended, hang up" would
    # cut the call off in the pause where somebody is deciding which key to
    # press.
    it "does not hang up when the reminder itself finishes speaking" do
      telnyx_post("call.speak.ended", call)

      expect(TelnyxVoiceService).not_to have_received(:hangup)
      expect(call.reload.outcome).to eq("pending")
    end
  end

  # A senior set to Spanish hears the farewell in Spanish, like everything else
  # the call says. A missing translation would speak the key name down the line.
  describe "in another language" do
    let(:senior) { create(:user, :senior, name: "Mamá", phone: "+15551234567", spoken_language: "es-US") }
    let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver) }
    let(:call) do
      TelnyxCall.reserve_verification(senior, requested_by: caregiver)
                .tap { |c| c.update!(call_control_id: "verify-es") }
    end

    it "speaks the farewell in the language the rest of the call used" do
      telnyx_post("call.answered", call)
      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:speak)
        .with(hash_including(message: /Gracias/, language: "es-US"))
    end
  end
end
