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

      telnyx_post("call.speak.ended", call)

      expect(TelnyxVoiceService).to have_received(:hangup)
    end

    # Silence is not a refusal and not an agreement. There is nothing to thank
    # them for and nothing they need to know, so the call simply ends.
    it "says nothing to somebody who pressed nothing" do
      telnyx_post("call.gather.ended", call, digits: "")

      expect(TelnyxVoiceService).not_to have_received(:speak)
        .with(hash_including(message: /Thank you/))
      expect(TelnyxVoiceService).to have_received(:hangup)
    end

    # speak swallows its own errors and answers nil. The call must still end --
    # the worst case is the abrupt ending this replaces, never a line left open
    # on somebody's telephone.
    it "still hangs up when the provider refuses to speak" do
      allow(TelnyxVoiceService).to receive(:speak).and_return(nil)

      telnyx_post("call.gather.ended", call, digits: "1")

      expect(TelnyxVoiceService).to have_received(:hangup)
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
