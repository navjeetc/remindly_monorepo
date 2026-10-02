# frozen_string_literal: true

# Double opt-in. A signup used to put an address on the list straight away, and
# a run of signups in September 2026 looked like subscription bombing: real
# people's addresses typed in by bots, each then sent the welcome email and
# synced to the CRM. Now an address joins only when its owner clicks the link
# emailed to it.
#
# Everyone already on the list is grandfathered as confirmed from the day they
# joined; their CRM contacts keep the remindly-unverified tag that marks them
# as never having confirmed.
class AddConfirmationToSubscribers < ActiveRecord::Migration[8.1]
  def up
    add_column :subscribers, :confirmed_at, :datetime
    add_column :subscribers, :confirmation_sent_at, :datetime
    add_index :subscribers, :confirmed_at

    execute "UPDATE subscribers SET confirmed_at = created_at WHERE confirmed_at IS NULL"
  end

  def down
    remove_index :subscribers, :confirmed_at
    remove_column :subscribers, :confirmation_sent_at
    remove_column :subscribers, :confirmed_at
  end
end
