# frozen_string_literal: true

# Which caregiver a care receiver counts against, on plans that limit how many
# parents a caregiver sets up. Written when it happens (creating the account,
# or being first to redeem the care receiver's token) rather than inferred
# later from link order, which follows when a token was made, not when it was
# redeemed. (Copilot on #226.)
#
# Backfilled from each care receiver's earliest caregiver link. That inference
# is the one this column replaces, and it is good enough here: nothing reads
# the column until paid plans start, and beta accounts get a year of Family.
class AddSetUpByToUsers < ActiveRecord::Migration[8.1]
  def up
    add_reference :users, :set_up_by, foreign_key: { to_table: :users, on_delete: :nullify }, null: true

    execute <<~SQL
      UPDATE users SET set_up_by_id = (
        SELECT caregiver_id FROM caregiver_links
        WHERE caregiver_links.senior_id = users.id AND caregiver_links.caregiver_id IS NOT NULL
        ORDER BY caregiver_links.created_at, caregiver_links.id
        LIMIT 1
      )
      WHERE users.role = 0
    SQL
  end

  def down
    remove_reference :users, :set_up_by, foreign_key: { to_table: :users }
  end
end
