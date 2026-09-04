# frozen_string_literal: true

# A bookmarkable URL that lets one device hear one care receiver's reminders
# without signing in. The secret in the address is the credential.
#
# No expiry column, deliberately. An expiring link reintroduces the exact
# failure this exists to remove: the tablet stops working, nothing announces it,
# and the first anyone knows is that acknowledgements stopped. `last_used_at`
# gives a caregiver visibility without a deadline, and `revoked_at` gives them
# an ending they choose.
class CreateReminderLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :reminder_links do |t|
      t.references :user, null: false, foreign_key: true

      # 32 bytes of urlsafe_base64, matching the pairing-token precedent. Unique
      # because the lookup is by token alone — there is no second factor to fall
      # back on if two rows ever collided.
      t.string :token, null: false

      t.datetime :revoked_at
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :reminder_links, :token, unique: true

    # Live links for one care receiver, which is what every screen asks for.
    add_index :reminder_links, [ :user_id, :revoked_at ]
  end
end
