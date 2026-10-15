# What the activation funnel on Admin → Traffic counts from.
#
# signup_source is the ?from= tag on the link a new account was created from —
# the same normalised tag PageCount tallies, so an ad's views and the accounts it
# produced line up under one name. first_signed_in_at is the first time the
# emailed link was opened: an account is created when the link is *requested*,
# so without it "signed up" would count everyone who typed an address.
#
# The backfill is an estimate, and only for accounts that already show they got
# in: one with an email and a role or name could only have chosen those after
# signing in. Their creation time stands in for the sign-in. Everyone else
# stays nil, which undercounts old sign-ins rather than inventing them.
class AddSignupTrackingToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :signup_source, :string
    add_column :users, :first_signed_in_at, :datetime

    execute <<~SQL
      UPDATE users
      SET first_signed_in_at = created_at
      WHERE email IS NOT NULL AND (role IS NOT NULL OR name IS NOT NULL)
    SQL
  end

  def down
    remove_column :users, :first_signed_in_at
    remove_column :users, :signup_source
  end
end
