require "rails_helper"
require Rails.root.join("db/migrate/20261014020000_add_signup_tracking_to_users")

# The backfill estimates first_signed_in_at for accounts that existed before it
# was recorded. Copilot on #206: the first version took a role as proof of a
# sign-in, and an invited caregiver is created with one before opening anything
# — so unopened invitations counted as activated, and their real first sign-in
# could never be recorded.
RSpec.describe AddSignupTrackingToUsers do
  def backfill
    ActiveRecord::Migration.suppress_messages { described_class.new.backfill }
  end

  it "estimates a sign-in for an account that saved a name, which needs one" do
    user = create(:user, :caregiver, name: "Navjeet")

    backfill

    expect(user.reload.first_signed_in_at).to be_within(1.second).of(user.created_at)
  end

  it "leaves an unopened invitation alone: a role alone proves nothing" do
    invitee = User.create!(email: "invited@example.com", role: :caregiver)

    backfill

    expect(invitee.reload.first_signed_in_at).to be_nil
  end

  it "leaves a care receiver with no email alone" do
    senior = User.create!(role: :senior, name: "Mum", tz: "America/New_York")

    backfill

    expect(senior.reload.first_signed_in_at).to be_nil
  end

  it "never overwrites a sign-in that was actually recorded" do
    recorded = 2.days.ago.change(usec: 0)
    user = create(:user, :caregiver, name: "Navjeet", first_signed_in_at: recorded)

    backfill

    expect(user.reload.first_signed_in_at).to eq(recorded)
  end
end
