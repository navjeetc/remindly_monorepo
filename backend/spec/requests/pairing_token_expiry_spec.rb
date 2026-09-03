require "rails_helper"

# A pairing token is a bearer credential over somebody's care record: redeeming
# one grants `manage`, which is permission to read their reminders, write their
# telephone number, and ask them to agree to automated calls.
#
# Both screens that hand one out have always printed a seven-day expiry. Nothing
# enforced it — redemption asked only whether the token existed and was
# unclaimed — so a token generated months earlier still paired, and the refusal
# message named a state the code could not produce.
RSpec.describe "A pairing token's week", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # The JSON endpoints authenticate with a Bearer token rather than the session
  # the dashboard uses. Both redemption paths are exercised here because both
  # asked the old question, and fixing one would have left the other open.
  def bearer(user)
    { "Authorization" => "Bearer #{JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i },
                                              ENV.fetch('JWT_SECRET', 'dev_secret_change_me'), 'HS256')}" }
  end

  # travel_to rather than updating created_at, so the model and the controller
  # read the same clock the application will.
  def token_generated(ago)
    travel_to(ago.ago) { CaregiverLink.generate_pairing_token(senior: senior) }
  end

  describe "redeeming through the JSON endpoint" do
    it "works inside the week" do
      link = token_generated(6.days)

      post "/caregiver_links/pair", params: { token: link.pairing_token }, headers: bearer(caregiver)

      expect(response).to have_http_status(:ok)
      expect(link.reload.caregiver).to eq(caregiver)
      expect(link.permission).to eq("manage")
    end

    # The whole point. Before this, the link paired and the caregiver silently
    # gained manage over an account whose owner had been told the token lapsed.
    it "is refused once the week has passed" do
      link = token_generated(8.days)

      expect {
        post "/caregiver_links/pair", params: { token: link.pairing_token }, headers: bearer(caregiver)
      }.not_to change { link.reload.caregiver }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(link.permission).to eq("view")
    end

    # Said plainly to somebody holding the exact token — they can already tell it
    # was real — so they ask for a new one instead of hunting for a typo.
    it "says the token expired rather than that it was never valid" do
      link = token_generated(8.days)

      post "/caregiver_links/pair", params: { token: link.pairing_token }, headers: bearer(caregiver)

      expect(response.parsed_body["error"]).to match(/expired.*generate a new one/i)
    end

    it "still says nothing about a token that never existed" do
      post "/caregiver_links/pair", params: { token: "not-a-real-token" }, headers: bearer(caregiver)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("Invalid or expired pairing token")
    end

    # The boundary belongs to the holder: a token in its final minutes is still
    # theirs to use.
    it "works up to the last minute of the week" do
      link = token_generated(CaregiverLink::PAIRING_TOKEN_TTL - 1.minute)

      post "/caregiver_links/pair", params: { token: link.pairing_token }, headers: bearer(caregiver)

      expect(link.reload.caregiver).to eq(caregiver)
    end
  end

  describe "redeeming through the dashboard" do
    it "is refused once the week has passed" do
      link = token_generated(8.days)
      sign_in(caregiver)

      post "/dashboard/pair", params: { token: link.pairing_token }

      expect(link.reload.caregiver).to be_nil
      expect(flash[:alert]).to match(/expired/i)
    end

    it "works inside the week" do
      link = token_generated(1.day)
      sign_in(caregiver)

      post "/dashboard/pair", params: { token: link.pairing_token }

      expect(link.reload.caregiver).to eq(caregiver)
    end
  end

  describe "what the care receiver is told" do
    # The printed date and the check behind it used to be computed in two places
    # from the same literal, free to drift apart. This is the guarantee that they
    # cannot: both read expires_at.
    it "prints the date the token actually stops working" do
      post "/caregiver_links/generate_token", headers: bearer(senior)

      link = CaregiverLink.find_by(senior_id: senior.id)
      expect(Time.parse(response.parsed_body["expires_at"])).to be_within(1.second).of(link.expires_at)
      expect(link.expires_at).to be_within(1.second).of(link.created_at + CaregiverLink::PAIRING_TOKEN_TTL)
    end
  end

  describe "an expired row" do
    # Refused, not deleted. A link somebody tried to redeem a month late is the
    # only record that the attempt happened.
    it "is kept, so a late attempt leaves a trail" do
      link = token_generated(8.days)

      post "/caregiver_links/pair", params: { token: link.pairing_token }, headers: bearer(caregiver)

      expect(CaregiverLink.exists?(link.id)).to be(true)
      expect(link.reload.pairing_token).to be_present
    end

    # pending? keeps its old meaning: nobody has claimed this. An expired row
    # still answers yes, and callers asking that question are entitled to it.
    it "is still unclaimed, and no longer redeemable" do
      link = token_generated(8.days)

      expect(link).to be_pending
      expect(link).to be_expired
      expect(link).not_to be_redeemable
    end
  end
end
