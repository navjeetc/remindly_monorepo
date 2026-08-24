# One live call per *telephone*, not per account.
#
# users.phone is not unique, so two user records can hold the same number — a
# couple sharing a landline, or a duplicate account. An index keyed on user_id
# arbitrates between accounts and lets both of them ring the same physical
# handset at once, which is the thing the claim exists to prevent.
#
# to_number is recorded on every attempt now, not only verifications, so the
# claim can be made against what will actually be dialled.
class ClaimTheLineByNumber < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE telnyx_calls
         SET to_number = (SELECT phone FROM users WHERE users.id = telnyx_calls.user_id)
       WHERE to_number IS NULL
    SQL

    remove_index :telnyx_calls, name: "index_telnyx_calls_one_live_call_per_user"
    add_index :telnyx_calls, :to_number, unique: true,
              where: "completed_at IS NULL AND to_number IS NOT NULL",
              name: "index_telnyx_calls_one_live_call_per_number"
  end

  def down
    remove_index :telnyx_calls, name: "index_telnyx_calls_one_live_call_per_number"
    add_index :telnyx_calls, :user_id, unique: true, where: "completed_at IS NULL",
              name: "index_telnyx_calls_one_live_call_per_user"
  end
end
