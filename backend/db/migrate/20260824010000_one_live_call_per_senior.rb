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
  def change
    add_index :telnyx_calls, :user_id, unique: true, where: "completed_at IS NULL",
              name: "index_telnyx_calls_one_live_call_per_user"
  end
end
