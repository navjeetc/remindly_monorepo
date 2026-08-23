# Makes the per-senior daily cap a constraint instead of a count-then-insert.
#
# The cap was checked by counting today's rows and then creating one, which
# three Solid Queue worker threads can all pass at once for three different
# occurrences — the per-occurrence unique index cannot arbitrate, because every
# occurrence id differs. A safety cap that a caregiver cannot configure away
# (invariant 7) should not be defeated by thread count.
#
# call_day is the date in the *senior's* zone, not UTC, because the cap is about
# how often their phone rings and a UTC boundary would cut their evening in
# half. daily_sequence numbers the attempts within that day, and the unique
# index means two reserves computing the same next number cannot both win.
class AddDailyAllowanceToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :call_day, :date
    add_column :telnyx_calls, :daily_sequence, :integer

    add_index :telnyx_calls, [ :user_id, :call_day, :daily_sequence ], unique: true,
              where: "call_day IS NOT NULL",
              name: "index_telnyx_calls_on_user_day_and_sequence"
  end
end
