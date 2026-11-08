# frozen_string_literal: true

# stripe_customer_id: the Stripe customer this account pays as. Created before
# the first Checkout, so the webhook can always find the account by it.
#
# family_granted_until: Family given rather than bought — the beta thank-you
# (a year from launch for everyone already using Remindly). Kept apart from
# family_until, which follows the Stripe subscription and is rewritten on
# every subscription event: a grant stored there would be overwritten the
# first time a beta user's card was charged or a subscription ended.
class AddBillingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :stripe_customer_id, :string
    add_index :users, :stripe_customer_id, unique: true
    add_column :users, :family_granted_until, :datetime
  end
end
