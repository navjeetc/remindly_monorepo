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

  # Switching used to be offered on the profile and was removed: it was one
  # click from a dashboard you could only return to by pressing it again, and
  # nothing recorded that it had happened. Refused in the model rather than only
  # hidden in the view, because a removed button with a live endpoint behind it
  # is not a removal.
  it "does not let a user change a role they have already chosen" do
    sign_in(new_user)
    new_user.update_column(:role, User.roles.fetch(:senior)) # integer-backed enum

    expect {
      patch "/select_role", params: { role: "caregiver" }
    }.not_to change { new_user.reload.role }
  end

  # The failure branch used to tell somebody who already had a role to "choose
  # whether you receive reminders or set them up for someone", which is a prompt
  # to do the thing the endpoint had just refused.
  it "tells a settled user their role rather than asking them to pick again" do
    sign_in(new_user)
    new_user.update_column(:role, User.roles.fetch(:senior))

    patch "/select_role", params: { role: "caregiver" }

    expect(flash[:alert]).to include("already set up as a care receiver")
    expect(flash[:alert]).not_to include("Please choose")
  end

  it "names the role the way the rest of the app does" do
    sign_in(new_user)

    patch "/select_role", params: { role: "senior" }

    expect(flash[:notice]).to include("care receiver")
    expect(flash[:notice]).not_to match(/\bsenior\b/i)
  end

  it "does not offer the switch on the profile either" do
    sign_in(new_user)
    new_user.update_column(:role, User.roles.fetch(:senior))

    get "/profile"
    text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

    expect(text).to include("You're set up as a care receiver")
    expect(text).not_to include("Switch to")
  end

  it "does not let a user self-grant admin" do
    sign_in(new_user)

    expect {
      patch "/select_role", params: { role: "admin" }
    }.not_to change { new_user.reload.role } # stays nil

    expect(new_user.reload.role).to be_nil
  end
end
