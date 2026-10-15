# What the activation funnel on Admin → Traffic counts from.
#
# signup_source is the ?from= tag on the link a new account was created from —
# the same normalised tag PageCount tallies, so an ad's views and the accounts it
# produced line up under one name. first_signed_in_at is the first time the
# emailed link was opened: an account is created when the link is *requested*,
# so without it "signed up" would count everyone who typed an address.
#
# The backfill is an estimate, and only for accounts that show they got in: a
# name can only be saved from the profile, after signing in (User validates it
# on update). A role is not enough — an invited caregiver is created with one
# before opening anything — so role-only accounts stay nil, and their first
# real sign-in records its own time. Creation time stands in for the sign-in.
# Undercounting old sign-ins is the safe direction; inventing them is not.
class AddSignupTrackingToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :signup_source, :string
    add_column :users, :first_signed_in_at, :datetime

    backfill
  end

  def down
    remove_column :users, :first_signed_in_at
    remove_column :users, :signup_source
  end

  def backfill
    execute <<~SQL
      UPDATE users
      SET first_signed_in_at = created_at
      WHERE first_signed_in_at IS NULL
        AND email IS NOT NULL
        AND TRIM(COALESCE(name, '')) != ''
    SQL
  end
end
