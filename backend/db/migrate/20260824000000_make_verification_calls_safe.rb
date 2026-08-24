# Three gaps a review found in the verification call, all of the same family:
# something decided from a value that could move between deciding and acting.
#
# 1. reserve_verification counted, then created, with no constraint behind it.
#    Two caregivers — or one double-click — could both read the same count and
#    both insert, exceeding the daily bound and producing two rows sharing an
#    attempt_number. The rescue for RecordNotUnique could never fire, because
#    nothing could raise it. The partial unique index gives it something to
#    catch. Partial because a reminder attempt_number restarts per occurrence,
#    so several reminder rows legitimately share (user, day, attempt_number).
#
# 2. Consent was recorded against users.phone as read at the moment of the
#    keypress, not the number actually dialled. A caregiver editing the number
#    while the call was ringing would have had the old handset's "1" enable
#    calls to a number nobody had agreed to — precisely the failure
#    "consent belongs to a number" exists to prevent. to_number records what was
#    dialled so the two can be compared.
#
# 3. The call named senior.caregivers.first as the person who arranged it, which
#    with several caregivers is arbitrary and may name the wrong one. That
#    undermines the only anti-scam signal the script has: a stranger could not
#    know who arranged this, but neither can we if we guess.
class MakeVerificationCallsSafe < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :to_number, :string
    add_reference :telnyx_calls, :requested_by, foreign_key: { to_table: :users }, null: true

    add_index :telnyx_calls, [ :user_id, :call_day, :attempt_number ],
              unique: true, where: "purpose = 'verification'",
              name: "index_telnyx_calls_on_user_day_and_verification_attempt"
  end
end
