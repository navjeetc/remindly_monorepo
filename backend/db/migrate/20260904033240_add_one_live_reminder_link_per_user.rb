# frozen_string_literal: true

# One live link per care receiver, enforced by the database rather than by the
# controller remembering to revoke the old one first.
#
# The controller does revoke first, inside a transaction, and that is almost
# always enough. Almost: two caregivers pressing "Create a device link" at the
# same moment could each revoke what they saw and mint what they wanted, leaving
# two live credentials where the panel shows one — and the invisible one is the
# one nobody revokes, because nobody knows it is there.
#
# Partial index, so revoked rows are exempt. They accumulate on purpose: a
# revoked link keeps its last_used_at, which is the only record that a device
# was ever really used.
class AddOneLiveReminderLinkPerUser < ActiveRecord::Migration[8.1]
  def change
    add_index :reminder_links, :user_id,
              unique: true,
              where: "revoked_at IS NULL",
              name: "index_reminder_links_one_live_per_user"
  end
end
