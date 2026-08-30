# frozen_string_literal: true

# One row per attempt, not one per occurrence.
#
# The table was created with a single row per (occurrence, user), reused by
# find_or_initialize_by on every dial. That made created_at permanently stale
# after the first call, which defeated the scheduler's "skip recently called"
# window entirely: an unanswered senior was re-dialled every minute until the
# missed sweep closed the occurrence an hour later. It also overwrote
# call_control_id each time, destroying the record of what had already happened.
#
# call_control_id becomes nullable because an attempt is now claimed *before*
# the provider is called, and the id only exists after. SQLite treats NULLs as
# distinct in a unique index, so several reserved rows coexist safely.
class AddAttemptNumberToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :attempt_number, :integer, null: false, default: 1

    change_column_null :telnyx_calls, :call_control_id, true

    # The constraint that decides a race. Two jobs computing the same next
    # attempt both try to insert; the database picks one and the loser is told
    # so before it dials, rather than after.
    add_index :telnyx_calls, [ :occurrence_id, :attempt_number ], unique: true,
              name: "index_telnyx_calls_on_occurrence_and_attempt"
  end
end
