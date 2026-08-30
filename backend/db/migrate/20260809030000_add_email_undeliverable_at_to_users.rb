# frozen_string_literal: true

# Records that a mail provider has permanently refused an address.
#
# CheckCoverageGapsJob mailed two demo accounts with invented addresses every
# morning from 2026-07-24 to 2026-08-09 — 44 failed jobs. Both had hard bounced
# ("unknown user, mailbox not found"), after which Postmark marks an address
# inactive and refuses every later send. The app had nowhere to put that fact,
# so it rediscovered it daily.
#
# A timestamp rather than a boolean: when an address went bad is the useful
# question when someone asks why they stopped hearing from us, and nil is an
# unambiguous "nothing wrong with this one".
class AddEmailUndeliverableAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_undeliverable_at, :datetime
  end
end
