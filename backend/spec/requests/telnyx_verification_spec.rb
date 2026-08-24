require "rails_helper"

# The verification call is the only thing in the application permitted to say a
# number may be telephoned. Everything else reads that decision; nothing else
# writes it.
RSpec.describe "Telnyx verification calls", type: :request do
  let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Jane", nickname: "Janey", email: "kid@example.com") }
  let(:call) { TelnyxCall.reserve_verification(senior).tap { |c| c.update!(call_control_id: "verify-1") } }

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
end
