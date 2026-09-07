# frozen_string_literal: true

# What stage a link is at, said explicitly rather than inferred.
#
# `pending?` has meant "caregiver_id is nil", and every caregiver action
# authorises through `current_user.caregiver_links` — so a link with no
# caregiver grants nothing, and one with a caregiver grants everything. Two
# states, decided by whether a foreign key happens to be filled in.
#
# Phase 3 needs a third: a caregiver has created an account for somebody and
# written reminders into it, but that person has not yet opened the link and
# agreed to any of it. That link must permit reminder authoring and refuse every
# activity, acknowledgement and coverage view — a distinction no null foreign
# key can carry, because the caregiver is present for both.
#
# Explicit, so authorisation splits on a stated fact rather than on the absence
# of data. See docs/SENIOR_ACCESS_DESIGN.md, "The states a link moves through".
class AddStateToCaregiverLinks < ActiveRecord::Migration[8.1]
  def up
    # Default provisional would be wrong for every row that exists; default
    # active would be wrong for the unredeemed tokens. Backfilled below instead,
    # from the fact that has decided this until now.
    add_column :caregiver_links, :state, :integer, null: false, default: 0

    # caregiver_id nil means nobody has redeemed the token: pending, unchanged.
    # Everything else is a live relationship the care receiver either started
    # themselves or accepted an invitation into, which is what active means.
    execute <<~SQL
      UPDATE caregiver_links SET state = 2 WHERE caregiver_id IS NOT NULL
    SQL

    add_index :caregiver_links, [ :senior_id, :state ]
  end

  def down
    remove_index :caregiver_links, [ :senior_id, :state ]
    remove_column :caregiver_links, :state
  end
end
