# frozen_string_literal: true

# Escalation calls: when a care receiver does not answer any of the calls for a
# time-critical reminder, Remindly rings the caregivers in an order the family
# chooses, one at a time, until somebody presses 1 to say they will check.
#
# caregiver_links.escalation_position is that order (1, 2, 3, or nil for not
# called). Unique per care receiver, so two caregivers cannot both be first.
#
# telnyx_calls.escalation_occurrence_id names the missed occurrence an
# escalation call is about. Not occurrence_id, deliberately: every reader of
# occurrence.telnyx_calls -- the missed email's "how many times we rang", the
# phone failure reason, the scheduler's retry spacing -- means the care
# receiver's own reminder calls, and a caregiver's call counted among them would
# make each one quietly wrong. attempt_number on these rows is the position in
# the order, and the index makes a duplicate job for the same position lose.
class AddEscalationCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :caregiver_links, :escalation_position, :integer
    add_index :caregiver_links, [ :senior_id, :escalation_position ],
      unique: true, where: "escalation_position IS NOT NULL",
      name: "index_caregiver_links_on_senior_and_escalation_position"

    add_reference :telnyx_calls, :escalation_occurrence, foreign_key: { to_table: :occurrences }, index: false
    add_index :telnyx_calls, [ :escalation_occurrence_id, :attempt_number ],
      unique: true, where: "purpose = 'escalation'",
      name: "index_telnyx_calls_on_escalated_occurrence_and_position"
  end
end
