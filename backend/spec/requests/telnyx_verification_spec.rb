require "rails_helper"

# The verification call is the only thing in the application permitted to say a
# number may be telephoned. Everything else reads that decision; nothing else
# writes it.
RSpec.describe "Telnyx verification calls", type: :request do
  let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Jane", nickname: "Janey", email: "kid@example.com") }
  let(:call) do
    TelnyxCall.reserve_verification(senior, requested_by: caregiver)
              .tap { |c| c.update!(call_control_id: "verify-1") }
  end

  def telnyx_post(event_type, payload = {})
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
    CaregiverLink.create!(senior: senior, caregiver: caregiver)
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  describe "what it asks" do
    # senior.caregivers.first was arbitrary with more than one caregiver, and
    # naming the wrong person destroys the only anti-scam signal the script has.
    it "names the caregiver who actually asked, not whichever link came first" do
      create(:user, :caregiver, name: "Someone Else", nickname: "Sam", email: "other@example.com")
        .then { |other| CaregiverLink.create!(senior: senior, caregiver: other) }

      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said).to include("Janey asked us")
      expect(said).not_to include("Sam")
    end

    it "names the caregiver who arranged it, which a stranger could not know" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said).to include("Janey asked us")
      expect(said).to include("Mom")
    end

    it "says what it will never ask for, before asking for anything" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said.index("never ask you for personal details")).to be < said.index("press 1")
    end

    # Cut deliberately: Remindly may be monetised, and a promise made in a
    # recorded call to an elderly person is not one to walk back.
    it "makes no promise about money" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said).not_to match(/money|payment|charge|free/i)
    end

    it "offers the way out in the very first call" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said).to include("press 9")
    end

    it "does not announce a reminder, because there is no dose to announce" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      telnyx_post("call.answered")

      expect(said).not_to include("with your reminder")
    end
  end

  describe "pressing 1" do
    it "is the only thing that lets Remindly telephone this number" do
      expect { telnyx_post("call.gather.ended", digits: "1") }
        .to change { senior.reload.call_reminders_enabled }.from(false).to(true)
    end

    it "records when they agreed, and that the number reached them" do
      telnyx_post("call.gather.ended", digits: "1")

      expect(senior.reload.call_consent_at).to be_present
      expect(senior.phone_verified_at).to be_present
      expect(call.reload.outcome).to eq("consented")
    end

    it "lifts a previous opt-out, since they have just agreed again" do
      senior.update!(call_opted_out_at: 1.week.ago)

      telnyx_post("call.gather.ended", digits: "1")

      expect(senior.reload.call_opted_out_at).to be_nil
    end
  end

  # Consent belongs to the number that agreed. A caregiver can edit the number
  # while this call is ringing, and a "1" from the old handset must not enable
  # calls to a number nobody has agreed to.
  describe "when the number changes mid-call" do
    it "ignores a keypress from the number that is no longer on file" do
      call # dialled while the old number was on file; the lets are lazy
      senior.update!(phone: "+15559998888")

      telnyx_post("call.gather.ended", digits: "1")

      expect(senior.reload.call_reminders_enabled).to be false
      expect(senior.call_consent_at).to be_nil
    end

    it "records it as declined rather than as agreement" do
      call
      senior.update!(phone: "+15559998888")

      telnyx_post("call.gather.ended", digits: "1")

      expect(call.reload.outcome).to eq("declined")
    end

    it "still honours an opt-out from the old handset, since stopping is theirs to say" do
      call
      senior.update!(phone: "+15559998888")

      telnyx_post("call.gather.ended", digits: "9")

      expect(senior.reload.call_opted_out_at).to be_present
    end
  end

  describe "pressing 9" do
    it "stops calls immediately and permanently" do
      telnyx_post("call.gather.ended", digits: "9")

      expect(senior.reload.call_opted_out_at).to be_present
      expect(senior.call_reminders_enabled).to be false
      expect(call.reload.outcome).to eq("opted_out")
    end

    it "does not record consent it never received" do
      telnyx_post("call.gather.ended", digits: "9")

      expect(senior.reload.call_consent_at).to be_nil
    end
  end

  # Saying nothing is not saying stop. Burning someone's opt-out on a silence
  # would take away the one thing that is supposed to be theirs to say.
  describe "pressing nothing" do
    it "is not consent" do
      telnyx_post("call.gather.ended", digits: "")

      expect(senior.reload.call_reminders_enabled).to be false
      expect(senior.call_consent_at).to be_nil
    end

    it "is not an opt-out either" do
      telnyx_post("call.gather.ended", digits: "")

      expect(senior.reload.call_opted_out_at).to be_nil
      expect(call.reload.outcome).to eq("declined")
    end

    it "leaves the caregiver free to try again" do
      telnyx_post("call.gather.ended", digits: "")

      expect(TelnyxCall.reserve_verification(senior)).to be_present
    end

    it "treats an unoffered digit the same way" do
      telnyx_post("call.gather.ended", digits: "5")

      expect(call.reload.outcome).to eq("declined")
      expect(senior.reload.call_opted_out_at).to be_nil
    end
  end

  it "never touches an occurrence, because it is about a number" do
    expect(call.occurrence_id).to be_nil

    telnyx_post("call.gather.ended", digits: "1")

    expect(Acknowledgement.count).to eq(0)
  end
  # A caregiver-created senior may have no name at all — SENIOR_ACCESS_DESIGN.md
  # contemplates exactly that. User validates name on update, so writing consent
  # with update! would raise, the webhook would answer 500, Telnyx would retry
  # into the same wall, and the senior could never stop the calls.
  describe "a senior with an incomplete profile" do
    let(:senior) { User.create!(email: "nameless@example.com", role: :senior, tz: "America/New_York", phone: "+15551234567") }

    it "can still say stop" do
      telnyx_post("call.gather.ended", digits: "9")

      expect(senior.reload.call_opted_out_at).to be_present
      expect(senior.call_reminders_enabled).to be false
    end

    it "can still agree" do
      telnyx_post("call.gather.ended", digits: "1")

      expect(senior.reload.call_consent_at).to be_present
      expect(senior.call_reminders_enabled).to be true
    end

    it "does not answer the provider with an error it would retry forever" do
      telnyx_post("call.gather.ended", digits: "9")

      expect(response).to have_http_status(:ok)
    end
  end

  # dial can succeed while writing call_control_id back fails. Reminder calls
  # recover through correlate; verification calls could not, because correlate
  # demanded an occurrence_id that a verification never has — so the senior
  # answered to silence and no keypress could reach us.
  describe "a callback that arrives before the call id was recorded" do
    it "adopts the reserved verification attempt" do
      reserved = TelnyxCall.reserve_verification(senior, requested_by: caregiver)

      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:not-recorded-yet",
            client_state: Base64.strict_encode64(
              { user_id: senior.id, attempt_number: reserved.attempt_number, purpose: "verification" }.to_json
            )
          }
        }
      }

      expect(reserved.reload.call_control_id).to eq("v3:not-recorded-yet")
      expect(reserved.answered_at).to be_present
    end

    it "still drops an event that names nothing we hold" do
      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:someone-elses",
            client_state: Base64.strict_encode64({ user_id: senior.id, attempt_number: 99, purpose: "verification" }.to_json)
          }
        }
      }

      expect(response).to have_http_status(:ok)
    end
  end
end
