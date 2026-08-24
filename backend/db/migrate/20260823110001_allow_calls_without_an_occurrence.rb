# A verification call is about a number, not a dose.
#
# telnyx_calls was built for reminder delivery, so occurrence_id is NOT NULL and
# every guard hangs off it. A call that asks someone whether they consent to be
# telephoned has no occurrence and never will.
#
# The alternative was a second table. It was rejected because the per-senior
# daily cap, the slot allocation, the in-flight guard and the cost record all
# live here: duplicating them is how an invariant quietly stops holding, and a
# senior could have taken ten reminder calls and ten verification calls in a day
# while both tables believed they were within their limit.
#
# purpose is NOT NULL with a default, so every existing row is a reminder call,
# which is what they all are.
class AllowCallsWithoutAnOccurrence < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :purpose, :string, null: false, default: "reminder"
    change_column_null :telnyx_calls, :occurrence_id, true

    # The (occurrence_id, attempt_number) index cannot constrain verification
    # calls, because SQLite treats NULLs as distinct. Their bound is per number
    # per day instead, and this index is what makes counting them cheap.
    add_index :telnyx_calls, [ :user_id, :purpose, :call_day ],
              name: "index_telnyx_calls_on_user_purpose_and_day"
  end
end
