require "rails_helper"

RSpec.describe RoleChangeMailer, type: :mailer do
  let(:user) { create(:user, :caregiver, name: "Kid", email: "kid@example.com") }
  let(:admin) { create(:user, :admin, name: "Admin", email: "admin@example.com") }
  let(:mail) { described_class.role_updated(user: user, old_role: "none", new_role: "caregiver", changed_by: admin) }

  it "addresses the user" do
    expect(mail.to).to eq([ user.email ])
  end

  # The button used to hardcode https://remindly.anakhsoft.com/dashboard; it must
  # now follow default_url_options — an absolute https URL on the canonical host,
  # never a relative path (which drops the host) and never the legacy domain.
  # Configure the mailer host as production does, since the test default is
  # example.com over http.
  it "links to the dashboard as an absolute https URL on the canonical host" do
    original = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = { host: "www.remindly.care", protocol: "https" }

    body = described_class.role_updated(user: user, old_role: "none", new_role: "caregiver", changed_by: admin).body.encoded
    expect(body).to include("https://www.remindly.care/dashboard")
    expect(body).not_to include("remindly.anakhsoft.com")
  ensure
    ActionMailer::Base.default_url_options = original
  end
end
