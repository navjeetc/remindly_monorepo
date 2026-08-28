require "rails_helper"
require "active_support/core_ext/object/with"
require Rails.root.join("db/migrate/20260828231943_grant_manage_to_existing_caregivers.rb")

# Everybody linked before this migration holds view, because nothing in the
# application ever granted anything else — so they are all locked out of the
# phone panel. Fixing the two creation paths only helps people who pair from
# now on; this catches the ones already here.
#
# The distinction worth pinning is between a link and an unclaimed token. Both
# are rows in the same table with permission = view, and only one of them
# belongs to a person.
RSpec.describe GrantManageToExistingCaregivers do
  let(:senior) { create(:user, :senior, name: "Nora") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam") }

  around { |example| ActiveRecord::Migration.with(verbose: false) { example.run } }

  it "gives an existing caregiver manage" do
    link = CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :view)

    described_class.new.up

    expect(link.reload.permission).to eq("manage")
  end

  it "leaves an unclaimed pairing token alone" do
    # A row with no caregiver is a token waiting to be claimed, not somebody
    # holding the wrong permission. pair_with sets it when the claim happens.
    token = CaregiverLink.generate_pairing_token(senior: senior)

    described_class.new.up

    expect(token.reload.permission).to eq("view")
    expect(token.caregiver_id).to be_nil
  end

  it "leaves a link that already had manage untouched" do
    link = CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)

    expect { described_class.new.up }.not_to change { link.reload.updated_at }
  end

  # Rolling back would have to guess which links were view by choice and which
  # were view because the application could not say otherwise. Nothing ever
  # chose, so there is nothing to restore.
  it "refuses to roll back rather than guessing" do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
