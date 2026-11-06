require "rails_helper"

RSpec.describe "Ending a caregiver link (dashboard#unlink)", type: :request do
  def sign_in(user)
    # Mirrors how the dashboard establishes a session after magic-link verify.
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  let(:senior)    { User.create!(email: "senior@example.com", role: :senior, name: "Senior", tz: "America/New_York") }
  let(:caregiver) { User.create!(email: "cg@example.com", role: :caregiver, name: "Care", tz: "America/New_York") }
  let!(:link)     { CaregiverLink.create!(senior: senior, caregiver: caregiver) }

  # The senior dashboard's "Remove Access" button pointed at this action, but it
  # only checked caregiver_links — so a senior clicking it 404'd and the caregiver
  # kept access to their reminders and care history.
  it "lets a senior revoke a caregiver's access" do
    sign_in(senior)

    expect {
      delete "/dashboard/unlink/#{link.id}"
    }.to change { CaregiverLink.exists?(link.id) }.from(true).to(false)

    expect(response).to redirect_to(dashboard_path)
  end

  it "still lets a caregiver remove themselves from a senior" do
    sign_in(caregiver)

    expect {
      delete "/dashboard/unlink/#{link.id}"
    }.to change { CaregiverLink.exists?(link.id) }.from(true).to(false)
  end

  # Only a party to the link may end it.
  it "does not let an unrelated user end someone else's link" do
    other = User.create!(email: "other@example.com", role: :caregiver, name: "Other", tz: "America/New_York")
    sign_in(other)

    expect {
      delete "/dashboard/unlink/#{link.id}"
    }.not_to change { CaregiverLink.exists?(link.id) }

    expect(response).to redirect_to(dashboard_path)
  end

  # 2026-11-05: a caregiver unlinked the person she had set up, who had no
  # email. The notice read "Unlinked from .", nothing was recorded, and the
  # reminder calls went on with nobody able to stop them.
  describe "the last caregiver of someone who cannot sign in" do
    let(:abby) do
      create(:user, :senior, :takes_calls, email: nil, name: "Abby", email_undeliverable_at: Time.current)
    end
    let!(:abby_link) { CaregiverLink.create!(senior: abby, caregiver: caregiver, permission: :manage, state: :active) }

    before { sign_in(caregiver) }

    it "warns before unlinking that the calls stop and the account is deleted" do
      get "/dashboard"

      button = Nokogiri::HTML(response.body).css("form[action='/dashboard/unlink/#{abby_link.id}'] button").first
      expect(button["onclick"]).to eq(
        "return confirm('Abby can\\'t sign in and has no other caregiver. Unlinking stops their " \
        "reminder calls now, and deletes their account and reminders in 30 days. Unlink?')"
      )
    end

    it "says who was unlinked, that the calls stopped, and that the account goes in 30 days" do
      delete "/dashboard/unlink/#{abby_link.id}"

      expect(flash[:notice]).to eq(
        "Unlinked from Abby. Abby's calls have stopped, and their account will be deleted in 30 days."
      )
      expect(abby.reload.callable_by_phone?).to be(false)
    end

    it "records the unlink for the audit log" do
      # A browser user agent: Ahoy records nothing for what it takes to be a bot.
      browser = { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15" }

      expect {
        delete "/dashboard/unlink/#{abby_link.id}", headers: browser
      }.to change { Ahoy::Event.where(name: "Caregiver Unlinked").count }.by(1)

      expect(Ahoy::Event.where(name: "Caregiver Unlinked").last.properties).to include(
        "senior_id" => abby.id, "caregiver_id" => caregiver.id, "by" => "caregiver"
      )
    end
  end
end
