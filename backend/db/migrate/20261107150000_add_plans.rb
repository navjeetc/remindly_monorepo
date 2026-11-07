# frozen_string_literal: true

# The two columns plans need before anyone can pay for one.
#
# users.family_until: the Family plan runs until this moment. Paying will set
# it; so will the beta thank-you (Family free for 12 months from the day paid
# plans start). Nil is the free plan. Nothing writes it yet, and nothing reads
# it while Plan.beta? is true.
#
# reminders.phone_call: whether this reminder rings the phone as well as
# showing on the screen. Every reminder rang until now, so existing rows keep
# ringing. It is what lets the free plan's fourth phone reminder of the day stay
# on the tablet instead of being refused.
class AddPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :family_until, :datetime
    add_column :reminders, :phone_call, :boolean, default: true, null: false
  end
end
