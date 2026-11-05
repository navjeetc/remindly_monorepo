# frozen_string_literal: true

require "rails_helper"

# Admin -> Users said "0 caregiver(s)" against every care receiver in
# production, including one with four active caregivers. It counted
# caregiver_links, the people a user cares for, which a care receiver never
# has. A care receiver a caregiver set up has no email either, so those rows
# showed no name at all.
RSpec.describe "Admin users list", type: :request do
  let(:admin) { create(:user, :caregiver, email: "admin@example.com", role: :admin) }
  let(:caregiver) { create(:user, :caregiver, email: "daughter@example.com") }
  let(:helper) { create(:user, :caregiver, email: "neighbour@example.com") }
  let(:senior) { create(:user, :senior, email: nil, name: "Abby", email_undeliverable_at: Time.current) }

  def sign_in_as(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # The row that starts with this text: a caregiver's row also mentions the
  # care receiver, under "Caring for".
  def row_for(text)
    Nokogiri::HTML(response.body).css("li").map { |li| li.text.squish }.find { |row| row.start_with?(text) }
  end

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active)
    CaregiverLink.create!(senior: senior, caregiver: helper, permission: :view, state: :provisional)
    sign_in_as(admin)
  end

  it "counts a care receiver's caregivers" do
    get "/admin/users"

    expect(row_for("Abby")).to include("2 caregivers")
  end

  it "names who cares for them, and which links they have not agreed to yet" do
    get "/admin/users"

    row = row_for("Abby")
    expect(row).to include("Cared for by:")
    expect(row).to include("daughter@example.com")
    expect(row).to include("neighbour@example.com (not yet agreed)")
    expect(row).not_to include("daughter@example.com (not yet agreed)")
  end

  it "shows the name of a care receiver who has no email" do
    get "/admin/users"

    expect(row_for("Abby")).to include("Abby (no email)")
  end

  it "does not count an invitation nobody has claimed" do
    CaregiverLink.create!(senior: senior, caregiver: nil, permission: :view, state: :pending,
                          pairing_token: "unclaimed-#{SecureRandom.hex(4)}")

    get "/admin/users"

    expect(row_for("Abby")).to include("2 caregivers")
  end

  it "still lists who a caregiver cares for" do
    get "/admin/users"

    row = row_for("daughter@example.com")
    expect(row).to include("1 care receiver")
    expect(row).to include("Caring for: Abby")
  end
end
