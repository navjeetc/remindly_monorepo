# frozen_string_literal: true

# An address that has left the mailing list but may still be in the CRM.
#
# Unsubscribing deletes the Subscriber row, and the privacy policy promises the
# address is deleted from the CRM too. While the CRM sync has no credentials it
# cannot do that, and once the row is gone nothing remembers the address needed
# removing. This is that memory, and only that: the row exists until the CRM
# removal succeeds, then is deleted with it.
class CreateCrmRemovals < ActiveRecord::Migration[8.1]
  def change
    create_table :crm_removals do |t|
      t.string :email, null: false
      t.timestamps
    end
    add_index :crm_removals, :email, unique: true
  end
end
