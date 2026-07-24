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
end
