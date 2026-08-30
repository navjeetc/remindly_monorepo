# frozen_string_literal: true

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
    # Only rows the new constraints need: the ones still in flight. A completed
    # call's destination is not knowable from users.phone, which may have been
    # edited since — filling it in would make every historical row claim it
    # dialled the current number, and an audit trail that confidently states
    # something false is worse than one that admits it does not know.
    execute <<~SQL
      UPDATE telnyx_calls
         SET to_number = (SELECT phone FROM users WHERE users.id = telnyx_calls.user_id)
       WHERE to_number IS NULL
         AND completed_at IS NULL
    SQL

    # Reconcile before constraining. The previous index arbitrated per account,
    # so two records sharing a handset could each hold an unfinished call —
    # which is the whole reason for this migration, and would make the new index
    # impossible to create. The entrypoint runs db:prepare at container start,
    # so a failure here aborts the boot rather than surfacing in a test.
    #
    # Two rows that both reached the provider cannot be resolved here. One of
    # them may be a live call, ending it needs the provider rather than the
    # database, and a migration that guesses would mark a connected call failed
    # without hanging it up — leaving its keypresses ignored, because the outcome
    # is no longer pending, while the senior is still on the line.
    #
    # So this refuses rather than guessing. It cannot happen from application
    # code: the per-user index added by the previous migration already forbids
    # two unfinished rows for one account, and a shared number needs two
    # accounts. If it somehow does, a deploy stopping with a legible message
    # beats a call orphaned in silence.
    duplicated = select_values(<<~SQL)
      SELECT to_number FROM telnyx_calls
       WHERE completed_at IS NULL AND to_number IS NOT NULL AND call_control_id IS NOT NULL
       GROUP BY to_number HAVING COUNT(*) > 1
    SQL

    if duplicated.any?
      raise ActiveRecord::IrreversibleMigration,
            "Two live provider calls share #{duplicated.join(', ')}. Hang one up in the " \
            "Telnyx portal and set its completed_at before deploying; picking one here " \
            "would orphan a call somebody may still be holding."
    end

    # A row holding a call_control_id is a call the provider accepted; one
    # without is a reservation that never rang. Insertion order is not liveness:
    # keeping the newest would sometimes keep an inert reservation and close the
    # real call underneath it — which does not hang that call up, and leaves its
    # keypresses ignored because the outcome is no longer pending.
    #
    # So a dialled row always outranks an undialled one, and the newest dialled
    # row wins among equals. Undialled duplicates are closed, which costs
    # nothing: they never reached the provider.
    execute <<~SQL
      UPDATE telnyx_calls
         SET completed_at = CURRENT_TIMESTAMP,
             status = 'failed',
             outcome = 'error',
             daily_sequence = NULL
       WHERE completed_at IS NULL
         AND to_number IS NOT NULL
         AND id NOT IN (
           SELECT id FROM telnyx_calls AS keep
            WHERE keep.completed_at IS NULL
              AND keep.to_number IS NOT NULL
              AND keep.id = (
                SELECT c.id FROM telnyx_calls AS c
                 WHERE c.completed_at IS NULL
                   AND c.to_number = keep.to_number
                 ORDER BY (c.call_control_id IS NOT NULL) DESC, c.id DESC
                 LIMIT 1
              )
         )
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
