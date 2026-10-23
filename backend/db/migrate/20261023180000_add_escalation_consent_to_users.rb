# frozen_string_literal: true

# A caregiver's agreement to be telephoned when somebody they look after misses
# an important reminder.
#
# Its own pair of columns rather than a reuse of call_consent_at and
# call_opted_out_at, which are a care receiver's agreement to reminder calls.
# Sharing them would let a caregiver's "yes, ring me about Mum" read as "ring me
# with reminders", and a caregiver's 9 would stop calls that are not about them.
#
# The index gives escalation-consent calls the same collision a verification has
# (two concurrent presses of the button cannot both take attempt 1) without the
# two purposes competing for attempt numbers on the same number.
# A caregiver's agreement to be telephoned when somebody they look after misses
# an important reminder (escalation calls).
#
# Separate from call_consent_at / call_reminders_enabled on purpose. Those are a
# care receiver's agreement to *reminder* calls, and the scheduler selects on
# them; reusing them would let "call me if Mum misses a dose" quietly sign the
# caregiver up for reminder calls of their own. The number itself is the shared
# users.phone, which a caregiver has never had any other use for.
#
# The escalation_consent verification calls get their own uniqueness index,
# matching the one reminder-consent verifications have, so two clicks of
# "Call me to confirm" cannot both claim attempt 1 for the same number and day.
class AddEscalationConsentToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :escalation_consent_at, :datetime
    add_column :users, :escalation_opted_out_at, :datetime

    add_index :telnyx_calls, [ :to_number, :call_day, :attempt_number ],
      unique: true,
      where: "purpose = 'escalation_consent' AND to_number IS NOT NULL",
      name: "index_telnyx_calls_on_number_day_and_escalation_consent_attempt"
  end
end
