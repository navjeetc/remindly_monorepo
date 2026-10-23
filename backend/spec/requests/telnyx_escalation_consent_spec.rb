require "rails_helper"

# The call a caregiver asks for from their own profile: may Remindly ring this
# number when somebody they look after misses an important reminder. It shares
# the verification call's machinery and none of its consequences -- above all,
# a caregiver's 9 stops calls to the caregiver and never reaches a care
# receiver's arrangement.
RSpec.describe "Telnyx escalation consent calls", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  let(:caregiver) { create(:user, :caregiver, name: "Christy", phone: "+15715550142", tz: "America/New_York") }
  let(:senior) do
    create(:user, :senior, name: "Mom", phone: "+15551234567", tz: "America/New_York",
           call_consent_at: 1.week.ago, phone_verified_at: 1.week.ago, call_reminders_enabled: true)
  end
  let(:call) do
    TelnyxCall.reserve_verification(caregiver, requested_by: caregiver, purpose: "escalation_consent")
              .tap { |c| c.update!(call_control_id: "escalate-1") }
  end

  def telnyx_post(event_type, payload = {})
    post "/telnyx/webhooks",
      params: { token: "test-token",
                data: { event_type: event_type, payload: payload.merge(call_control_id: call.call_control_id) } }
  end

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver)
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)
    allow(TelnyxVoiceService).to receive(:speak).and_return({ "data" => { "result" => "ok" } })
    allow(TelnyxVoiceService).to receive(:hangup!)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  describe "what it asks" do
    # Memoised: the pickup is answered once, and a second delivery is ignored.
    def spoken
      @spoken ||= begin
        said = nil
        allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw }
        telnyx_post("call.answered")
        said
      end
    end

    it "asks about missed reminders, not about reminder calls to the caregiver" do
      expect(spoken[:prompt]).to include("misses an important reminder")
      expect(spoken[:prompt]).not_to include("calling for")
    end

    it "offers both keys" do
      expect(spoken[:prompt]).to include("press 1").and include("press 9")
    end

    # A caregiver has no spoken-language setting, and these words exist only in
    # English. Even when the person they look after hears Spanish.
    it "speaks English, whatever the care receiver's language" do
      senior.update!(spoken_language: "es-US")

      expect(spoken[:language]).to eq("en-US")
    end
  end

  describe "pressing 1" do
    it "records the caregiver's agreement" do
      telnyx_post("call.gather.ended", digits: "1")

      expect(caregiver.reload).to be_escalation_callable
      expect(call.reload.outcome).to eq("consented")
    end

    it "lifts an earlier opt-out, since they asked for this call themselves" do
      caregiver.update_columns(escalation_opted_out_at: 1.week.ago)

      telnyx_post("call.gather.ended", digits: "1")

      expect(caregiver.reload.escalation_opted_out_at).to be_nil
    end

    # The caregiver's agreement to be rung is not the caregiver agreeing to
    # reminder calls of their own.
    it "does not make the caregiver callable for reminders" do
      telnyx_post("call.gather.ended", digits: "1")

      expect(caregiver.reload.call_consent_at).to be_nil
      expect(caregiver).not_to be_callable_by_phone
    end

    it "says a goodbye that promises only what they agreed to" do
      said = nil
      allow(TelnyxVoiceService).to receive(:speak) { |**kw| said = kw[:message]; { "data" => { "result" => "ok" } } }

      telnyx_post("call.gather.ended", digits: "1")

      expect(said).to include("important reminder is missed")
      expect(said).not_to include("time for a reminder")
    end
  end

  describe "pressing 9" do
    it "stops escalation calls to the caregiver" do
      telnyx_post("call.gather.ended", digits: "9")

      expect(caregiver.reload.escalation_opted_out_at).to be_present
      expect(caregiver).not_to be_escalation_callable
      expect(call.reload.outcome).to eq("opted_out")
    end

    # The reason this is its own purpose. On a verification call 9 refuses the
    # whole arrangement; here it must leave the care receiver's calls alone.
    it "leaves the care receiver's calls, and the link to them, exactly as they were" do
      link = CaregiverLink.find_by!(senior: senior, caregiver: caregiver)

      expect { telnyx_post("call.gather.ended", digits: "9") }
        .not_to(change { [ senior.reload.attributes.slice("call_reminders_enabled", "call_opted_out_at", "call_consent_at"),
                           link.reload.attributes ] })
    end

    it "does not touch the caregiver's own reminder-call settings" do
      expect { telnyx_post("call.gather.ended", digits: "9") }
        .not_to(change { caregiver.reload.call_opted_out_at })
    end

    it "says the escalation goodbye, not the care receiver's" do
      said = nil
      allow(TelnyxVoiceService).to receive(:speak) { |**kw| said = kw[:message]; { "data" => { "result" => "ok" } } }

      telnyx_post("call.gather.ended", digits: "9")

      expect(said).to include("missed reminders")
    end
  end

  describe "pressing nothing" do
    it "is neither agreement nor opt-out" do
      telnyx_post("call.gather.ended", digits: "")

      expect(caregiver.reload.escalation_consent_at).to be_nil
      expect(caregiver.escalation_opted_out_at).to be_nil
      expect(call.reload.outcome).to eq("declined")
    end
  end

  describe "when the number changes mid-call" do
    it "ignores a 1 from the number that is no longer on file" do
      call
      caregiver.update!(phone: "+15715550199")

      telnyx_post("call.gather.ended", digits: "1")

      expect(caregiver.reload.escalation_consent_at).to be_nil
      expect(call.reload.outcome).to eq("declined")
    end
  end

  describe "a callback that arrives before the call id was recorded" do
    it "adopts the reserved escalation-consent attempt" do
      reserved = TelnyxCall.reserve_verification(caregiver, purpose: "escalation_consent")

      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:not-recorded-yet",
            client_state: Base64.strict_encode64(
              { user_id: caregiver.id, attempt_number: reserved.attempt_number,
                call_day: reserved.call_day.to_s, purpose: "escalation_consent" }.to_json
            )
          }
        }
      }

      expect(reserved.reload.call_control_id).to eq("v3:not-recorded-yet")
      expect(reserved.answered_at).to be_present
    end
  end
end
