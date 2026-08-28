require "rails_helper"

# Nothing in the application ever granted manage. The column defaults to view,
# pair_with never touched it, and no screen could change it — so every caregiver
# who paired the documented way was permanently locked out of the phone panel:
# no number, no verification call, no call language. The headline feature was
# unreachable by anyone who joined normally, and it took walking a brand-new
# pair through pairing to see it, because every existing link in development had
# been set to manage by hand.
RSpec.describe "What pairing grants", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam") }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  describe "a token the care receiver handed over" do
    it "grants manage, so the phone panel can actually be used" do
      link = CaregiverLink.generate_pairing_token(senior: senior)
      sign_in(caregiver)

      post "/dashboard/pair", params: { token: link.pairing_token }

      expect(link.reload.caregiver).to eq(caregiver)
      expect(link.permission).to eq("manage")
    end

    it "lets that caregiver save a number, which is the thing that was blocked" do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)

      link = CaregiverLink.generate_pairing_token(senior: senior)
      sign_in(caregiver)
      post "/dashboard/pair", params: { token: link.pairing_token }

      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "+15551234567" } }

      expect(senior.reload.phone).to eq("+15551234567")
    end

    # The grant is "may ask", not "may enable". Consent is still only written by
    # a keypress on a call the care receiver answers.
    it "does not make anybody callable on its own" do
      link = CaregiverLink.generate_pairing_token(senior: senior)
      sign_in(caregiver)
      post "/dashboard/pair", params: { token: link.pairing_token }
      senior.update!(phone: "+15551234567")

      expect(senior.reload.callable_by_phone?).to be false
    end
  end

  # The invite screen promised view access and said permissions could be changed
  # later. The first became false with this change; the second was never true,
  # since no screen for changing a permission has ever existed. An inviter was
  # therefore handing over the telephone without being told.
  describe "what the invite screen promises" do
    it "does not promise view access it no longer grants" do
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
      sign_in(caregiver)

      get "/dashboard/senior/#{senior.id}/invite_caregiver"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      # Asserted on rendered text, not markup: an earlier version of this spec
      # looked for "view</strong> access" *after* stripping tags, so it could
      # never fail — which is worse than no assertion, because it reads as one.
      expect(text).not_to include("view access by default")
      expect(text).not_to include("change their permissions later")
      expect(text).not_to match(/\bview\b.{0,20}access/i)
    end

    it "says what the invitee will actually be able to do" do
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
      sign_in(caregiver)

      get "/dashboard/senior/#{senior.id}/invite_caregiver"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      expect(text).to include("everything you can for #{senior.display_name}")
      expect(text).to include("no way to reduce that afterwards")
      expect(text).to include("cannot do is agree to the calls")
    end
  end

  describe "an invitation from another caregiver" do
    # Same grant as pairing: a caregiver is a caregiver. This does widen who can
    # arrange calls — any linked caregiver may invite another, and the care
    # receiver is not asked — but it cannot start a call, because consent is
    # still only written by a keypress on one they answer.
    it "also grants manage" do
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
      invited = create(:user, :caregiver, name: "Alex", email: "alex@example.com")
      sign_in(caregiver)

      post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: invited.email }

      expect(CaregiverLink.find_by(senior: senior, caregiver: invited).permission).to eq("manage")
    end
  end
end
