require "rails_helper"

RSpec.describe RoleChangeMailer, type: :mailer do
  let(:user) { create(:user, :caregiver, name: "Kid", email: "kid@example.com") }
  let(:admin) { create(:user, :admin, name: "Admin", email: "admin@example.com") }
  let(:mail) { described_class.role_updated(user: user, old_role: "none", new_role: "caregiver", changed_by: admin) }

  it "addresses the user" do
    expect(mail.to).to eq([ user.email ])
  end

  # The button used to hardcode https://remindly.anakhsoft.com/dashboard; it must
  # follow default_url_options (the canonical host) instead of the legacy domain.
  it "links to the dashboard on the configured host, not the legacy domain" do
    expect(mail.body.encoded).to include("/dashboard")
    expect(mail.body.encoded).not_to include("remindly.anakhsoft.com")
  end
end
