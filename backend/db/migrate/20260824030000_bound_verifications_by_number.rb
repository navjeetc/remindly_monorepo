# The verification allowance was counted per account, and the account is not the
# thing that rings. users.phone is explicitly non-unique, so two records sharing
# a landline each carried their own five attempts — ten calls to one handset,
# defeating the bound that exists to stop exactly that.
#
# Keyed on the number and the day now, matching the live-call claim.
class BoundVerificationsByNumber < ActiveRecord::Migration[8.1]
  def up
    remove_index :telnyx_calls, name: "index_telnyx_calls_on_user_day_and_verification_attempt"
    add_index :telnyx_calls, [ :to_number, :call_day, :attempt_number ],
              unique: true, where: "purpose = 'verification' AND to_number IS NOT NULL",
              name: "index_telnyx_calls_on_number_day_and_verification_attempt"
  end

  def down
    remove_index :telnyx_calls, name: "index_telnyx_calls_on_number_day_and_verification_attempt"
    add_index :telnyx_calls, [ :user_id, :call_day, :attempt_number ],
              unique: true, where: "purpose = 'verification'",
              name: "index_telnyx_calls_on_user_day_and_verification_attempt"
  end
end
