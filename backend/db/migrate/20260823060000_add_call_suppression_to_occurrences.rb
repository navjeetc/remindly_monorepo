# frozen_string_literal: true

# Records that a call was withheld, rather than inferring it afterwards.
#
# The reason was being derived at notification time from scheduled_at, which
# gets the answer wrong whenever the decision and the schedule disagree: an
# 8:59pm reminder whose job runs at 9:01 is refused for being out of hours, but
# scheduled_at still reads 8:59, so the caregiver was told the senior had not
# marked it done. The same happens whenever the scheduler is down for an
# in-hours occurrence — no call, no record, and the blame lands on the senior.
#
# What was decided, and when, is a fact about a delivery attempt. It belongs in
# a column rather than in a re-computation against a clock that has since moved.
class AddCallSuppressionToOccurrences < ActiveRecord::Migration[8.1]
  def change
    add_column :occurrences, :call_suppressed_at, :datetime
    add_column :occurrences, :call_suppressed_reason, :string
  end
end
