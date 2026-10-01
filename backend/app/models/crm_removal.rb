# frozen_string_literal: true

# An address waiting to be removed from the CRM after leaving the mailing list.
# Kept only until that removal succeeds; see the migration for why it exists.
class CrmRemoval < ApplicationRecord
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  def self.record(email)
    create_or_find_by!(email: email)
  end

  def self.clear(email)
    where(email: email.to_s.strip.downcase).delete_all
  end
end
