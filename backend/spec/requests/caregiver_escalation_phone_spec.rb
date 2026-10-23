require "rails_helper"

# A caregiver's own number, kept for escalation calls: when somebody they look
# after misses an important reminder, Remindly may ring them. These are the
# profile half -- saving the number and asking for the call that confirms it.
# What the call says and what each key does is telnyx_escalation_consent_spec.
RSpec.describe "Caregiver escalation phone", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Mid-morning in New York, inside the default calling hours.
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)

  let(:caregiver) { create(:user, :caregiver, name: "Christy", tz: "America/New_York") }
  let(:flags) { { phone_call_reminders: true, escalation_calls: true } }

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    flags.each { |name, on| allow(FeatureFlag).to receive(:enabled?).with(name).and_return(on) }
    allow(TelnyxVoiceService).to receive(:verify).and_return({ "data" => { "call_control_id" => "v3:abc" } })
    sign_in(caregiver)
  end

  describe "the profile field" do
    it "is offered to a caregiver" do
      get "/profile"

      expect(doc.at_css("input[name='user[phone]']")["class"]).to include("field")
    end

    it "saves the number in the form the calls dial" do
      patch "/profile", params: { user: { phone: "(571) 555-0142" } }

      expect(caregiver.reload.phone).to eq("+15715550142")
    end

    # The field is shown formatted, so every save submits the formatted number.
    # If that read as a change, pressing Save to rename yourself would quietly
    # throw away the agreement the confirm call recorded.
    it "keeps a confirmed number confirmed when the profile is saved unchanged" do
      caregiver.update!(phone: "+15715550142")
      caregiver.update_columns(escalation_consent_at: 1.day.ago)

      get "/profile"
      shown = doc.at_css("input[name='user[phone]']")["value"]
      patch "/profile", params: { user: { name: "Christy O", phone: shown } }

      expect(caregiver.reload.escalation_consent_at).to be_present
    end

    it "forgets the agreement when the number changes, since another handset never gave it" do
      caregiver.update!(phone: "+15715550142")
      caregiver.update_columns(escalation_consent_at: 1.day.ago)

      patch "/profile", params: { user: { phone: "(571) 555-0199" } }

      expect(caregiver.reload.escalation_consent_at).to be_nil
      expect(caregiver).not_to be_escalation_callable
    end

    it "refuses a number the calls could not dial" do
      patch "/profile", params: { user: { phone: "12" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(caregiver.reload.phone).to be_nil
    end

    context "for a care receiver" do
      let(:caregiver) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

      # A care receiver's number is proposed by their caregiver and agreed to on
      # a call. A profile field would be a way round both.
      it "is neither shown nor saved" do
        get "/profile"
        expect(doc.at_css("input[name='user[phone]']")).to be_nil

        patch "/profile", params: { user: { phone: "(571) 555-0142" } }
        expect(caregiver.reload.phone).to be_nil
      end
    end

    context "while escalation calls are switched off" do
      let(:flags) { { phone_call_reminders: true, escalation_calls: false } }

      # Nothing places an escalation call yet, so the field would promise one.
      it "is neither shown nor saved" do
        get "/profile"
        expect(doc.at_css("input[name='user[phone]']")).to be_nil

        patch "/profile", params: { user: { phone: "(571) 555-0142" } }
        expect(caregiver.reload.phone).to be_nil
      end
    end
  end

  describe "the confirm call" do
    before { caregiver.update!(phone: "+15715550142") }

    it "is offered once there is a number" do
      get "/profile"

      expect(doc.at_css("form[action='/profile/confirm_phone'] button").text).to include("Call me to confirm")
    end

    it "rings the caregiver's number, as an escalation-consent call" do
      expect { post "/profile/confirm_phone" }.to change(TelnyxCall.escalation_consents, :count).by(1)

      call = TelnyxCall.last
      expect(call.user).to eq(caregiver)
      expect(call.to_number).to eq("+15715550142")
      expect(TelnyxVoiceService).to have_received(:verify).with(call)
      expect(flash[:notice]).to include("571-555-0142")
    end

    # A caregiver's tries must not use up the care receiver verification bound
    # for the same number, or the other way round.
    it "is counted apart from care receiver verifications" do
      post "/profile/confirm_phone"

      expect(TelnyxCall.verifications_in_window("+15715550142").count).to eq(0)
    end

    it "does not ring a number that is already confirmed" do
      caregiver.update_columns(escalation_consent_at: 1.hour.ago)

      expect { post "/profile/confirm_phone" }.not_to change(TelnyxCall, :count)
      expect(flash[:notice]).to include("already confirmed")
    end

    it "does not ring outside the caregiver's calling hours" do
      travel 13.hours # 11pm in New York

      expect { post "/profile/confirm_phone" }.not_to change(TelnyxCall, :count)

      expect(flash[:alert]).to include("only place calls")
    end

    it "stops at the daily bound" do
      TelnyxCall::MAX_VERIFICATIONS_PER_DAY.times do |i|
        TelnyxCall.reserve_verification(caregiver, purpose: "escalation_consent")
                  .update!(status: "completed", completed_at: Time.current - i.minutes)
      end

      expect { post "/profile/confirm_phone" }.not_to change(TelnyxCall, :count)
      expect(flash[:alert]).to include("Try again tomorrow")
    end

    it "does not dial into a call that is still live" do
      post "/profile/confirm_phone"

      expect { post "/profile/confirm_phone" }.not_to change(TelnyxCall, :count)
      expect(flash[:alert]).to include("already a call")
    end

    it "asks for a number before there is one" do
      caregiver.update!(phone: nil)

      expect { post "/profile/confirm_phone" }.not_to change(TelnyxCall, :count)
      expect(flash[:alert]).to include("Add your phone number")
    end

    context "for a care receiver" do
      let(:caregiver) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

      it "is refused" do
        post "/profile/confirm_phone"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "while escalation calls are switched off" do
      let(:flags) { { phone_call_reminders: true, escalation_calls: false } }

      it "is refused" do
        post "/profile/confirm_phone"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
