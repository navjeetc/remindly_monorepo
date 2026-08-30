# frozen_string_literal: true

# One live call per person, enforced by the database rather than by a read.
#
# call_in_flight? was a SELECT, so two reservations could both observe an idle
# line and both insert. The existing unique indexes could not arbitrate: a
# verification holds no daily_sequence and has no occurrence, so a verification
# racing a reminder collides on nothing at all. That is the same "two calls in
# one second to one phone" bug a live test caught in the delivery work, reached
# by a different route.
#
# Partial on completed_at because a call that has ended is not occupying the
# line, and reserve expires anything older than IN_FLIGHT_WINDOW before claiming
# — so a row abandoned by a dead worker cannot hold a senior's line for ever.
class OneLiveCallPerSenior < ActiveRecord::Migration[8.1]
  def up
    # Close anything already unfinished before demanding uniqueness. Several
    # unfinished rows per user are entirely possible under the pre-change code:
    # release_slot! cleared daily_sequence without setting completed_at, so a
    # run of provider failures left rows that were over in practice and open in
    # the database. Without this the index cannot be created, and because the
    # entrypoint runs db:prepare at container start, that aborts the boot before
    # the later number-based migration gets a chance to reconcile anything.
    # Insertion order is not liveness. MAX(id) here would sometimes keep a
    # reservation that never rang and close the dialled row underneath it --
    # which does not hang that call up, and leaves its keypresses ignored,
    # because the outcome is no longer pending while the senior is still on the
    # line. A row holding a call_control_id is a call the provider accepted; one
    # without never reached it and costs nothing to close.
    #
    # The same rule as the number-keyed migration that follows this one, and for
    # the same reason. It has to be applied here too, because this migration runs
    # first and the later one cannot undo a live call closed by this one.
    execute <<~SQL
      UPDATE telnyx_calls
         SET completed_at = CURRENT_TIMESTAMP,
             status = 'failed',
             outcome = 'error',
             daily_sequence = NULL
       WHERE completed_at IS NULL
         AND id NOT IN (
           SELECT keep.id FROM telnyx_calls AS keep
            WHERE keep.completed_at IS NULL
              AND keep.id = (
                SELECT c.id FROM telnyx_calls AS c
                 WHERE c.completed_at IS NULL
                   AND c.user_id = keep.user_id
                 ORDER BY (c.call_control_id IS NOT NULL) DESC, c.id DESC
                 LIMIT 1
              )
         )
    SQL

    add_index :telnyx_calls, :user_id, unique: true, where: "completed_at IS NULL",
              name: "index_telnyx_calls_one_live_call_per_user"
  end

  def down
    remove_index :telnyx_calls, name: "index_telnyx_calls_one_live_call_per_user"
  end
end
