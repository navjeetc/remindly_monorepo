# frozen_string_literal: true

require "rails_helper"

# The panel told caregivers to save "this number" for as long as the feature has
# existed and never printed one, because the value lived in credentials. In
# production that instruction was unfollowable on the step everything else
# depends on: the first caregiver's two consent calls were answered and dropped
# within four seconds with no keypress -- a screening handset -- and she reported
# that Remindly had never rung her.
#
# These pin the number being reachable by a human: on the screen, in a contact
# file, and in a message the caregiver can send to the person who owns the phone.
RSpec.describe "Saving Remindly's number as a contact", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # The panel's verification block is hidden outside the senior's calling hours,
  # and part of what these examples read sits inside it.
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York", phone: "+15551234567") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
    allow(TelnyxVoiceService).to receive(:caller_id_number).and_return("+15715170980")

    sign_in(caregiver)
  end

  describe "the phone panel" do
    before { get "/dashboard/senior/#{senior.id}" }

    # Grouped, not raw E.164. Somebody is copying this onto a handset or reading
    # it down a telephone.
    it "prints the number we call from" do
      expect(response.body).to include("+1 571-517-0980")
    end

    it "says what to save it as" do
      expect(response.body).to match(/save.{0,80}Remindly/im)
    end

    it "offers the contact card" do
      expect(response.body).to include(caller_id_card_path)
    end

    # The caregiver is usually not the person holding the phone that has to hold
    # the contact. Without something to forward, this step is relayed from
    # memory.
    it "offers a message the caregiver can send on" do
      expect(response.body).to include("save this number in your contacts as Remindly")
      expect(response.body).to match(/answer and press 1/i)
    end

    # The number is no use to somebody whose mother has lost the handset it was
    # saved on, if it disappears from the screen the moment setup succeeds.
    it "still names the number after they have agreed" do
      senior.update_columns(phone_verified_at: Time.current, call_consent_at: Time.current,
                            call_reminders_enabled: true)

      get "/dashboard/senior/#{senior.id}"

      expect(response.body).to include("+1 571-517-0980")
    end
  end

  describe "the contact card" do
    it "is a vCard naming Remindly and the number" do
      get caller_id_card_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vcard")
      expect(response.body).to include("FN:Remindly")
      expect(response.body).to include("TEL;TYPE=VOICE:+15715170980")
    end

    # Bare newlines import with empty fields on some handsets rather than
    # failing, which is worse: the caregiver believes the number is saved.
    it "separates lines with CRLF, as the format requires" do
      get caller_id_card_path

      expect(response.body).to include("BEGIN:VCARD\r\nVERSION:3.0\r\n")
    end

    it "downloads as a file rather than rendering" do
      get caller_id_card_path

      expect(response.headers["Content-Disposition"]).to include("Remindly.vcf")
    end

    it "is refused when reminder calls are switched off" do
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)

      get caller_id_card_path

      expect(response).to have_http_status(:forbidden)
    end

    # An unconfigured integration has no number to hand out, and a card holding
    # an empty TEL is a contact somebody saves and trusts.
    it "is not found when no number is configured" do
      allow(TelnyxVoiceService).to receive(:caller_id_number).and_return(nil)

      get caller_id_card_path

      expect(response).to have_http_status(:not_found)
    end

    it "is refused to a stranger" do
      delete "/logout" if Rails.application.routes.url_helpers.respond_to?(:logout_path)
      reset!

      get caller_id_card_path

      expect(response).to have_http_status(:found).or have_http_status(:unauthorized)
    end
  end

  describe "formatting" do
    it "leaves a number it cannot group unchanged" do
      expect(helper_formatted("+442071234567")).to eq("+442071234567")
    end

    # ApplicationController is an API controller and has no .helpers, so the
    # module is mixed into a bare object rather than reached through a view.
    def helper_formatted(number)
      Class.new { include ApplicationHelper }.new.formatted_phone_number(number)
    end
  end
end
