# frozen_string_literal: true

# Consent to be telephoned, recorded durably.
#
# These live on users rather than in the audit trail because PruneAnalyticsJob
# deletes Ahoy::Event at ninety days, and a record of who agreed to be called has
# to outlive that by years -- it is the thing that may have to be produced later,
# not a page view.
#
# phone_verified_at and call_consent_at look redundant and are not. The first
# says a call to this number was answered by someone who agreed; the second is
# the dated record of the agreement itself. Keeping them apart leaves room for
# re-verifying a number without restating consent, or recording consent obtained
# some other way, with neither fact overwriting the other.
class AddCallConsentToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone_verified_at, :datetime
    add_column :users, :call_consent_at, :datetime
    add_column :users, :call_opted_out_at, :datetime
  end
end
