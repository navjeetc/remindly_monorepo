require "rails_helper"

RSpec.describe "Self-serve role onboarding", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # A brand-new account: created by magic-link, no role yet, no name.
  let(:new_user) { User.create!(email: "new@example.com", tz: "America/New_York") }

  it "shows the role chooser (not a dead-end approval page) to a role-less user" do
    sign_in(new_user)
    get "/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome to Remindly")
    expect(response.body).to include("I'll be receiving the reminders")
    expect(response.body).to include("setting Remindly up for someone")
    # No admin waiting: the old copy is gone.
    expect(response.body).not_to include("Pending Approval")
  end

  it "sets the chosen role and lands the user in the app" do
    sign_in(new_user)

    expect {
      patch "/select_role", params: { role: "caregiver" }
    }.to change { new_user.reload.role }.from(nil).to("caregiver")

    expect(response).to redirect_to(dashboard_path)
  end

  it "lets a user switch their role later" do
    sign_in(new_user)
    new_user.update_column(:role, "senior")

    expect {
      patch "/select_role", params: { role: "caregiver" }
    }.to change { new_user.reload.role }.from("senior").to("caregiver")
  end

  it "does not let a user self-grant admin" do
    sign_in(new_user)

    expect {
      patch "/select_role", params: { role: "admin" }
    }.not_to change { new_user.reload.role } # stays nil

    expect(new_user.reload.role).to be_nil
  end
end
