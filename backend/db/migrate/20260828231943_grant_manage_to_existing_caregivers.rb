# A caregiver linked before this point almost certainly holds view, because
# nothing in the application ever granted anything else: the column defaults to
# view, pair_with never touched it, and no screen could change it. Any manage
# link that does exist was written by hand or by seed data — production has
# exactly one — and is left alone.
#
# The rest are locked out of the phone panel: no number, no verification call,
# no call language, which is the feature the product leads with.
#
# Fixing the two creation paths only helps people who pair from now on. This
# catches the ones already here.
#
# Only links that have a caregiver. An unclaimed pairing token is a row with a
# null caregiver_id waiting to be claimed, and pair_with sets the permission
# itself when that happens.
class GrantManageToExistingCaregivers < ActiveRecord::Migration[8.1]
  def up
    # Written as raw SQL rather than through the model on purpose: a data
    # migration that goes through CaregiverLink would break the day somebody
    # adds a validation or a callback, and it would then break in a migration
    # rather than anywhere a test would notice.
    # Named locally rather than read from CaregiverLink. A migration that asks
    # the model for its enum breaks the day somebody reorders it, and pinning
    # the integers here is the point: this migration means the values as they
    # are today, not whatever they become.
    view, manage = 0, 1

    execute <<~SQL
      UPDATE caregiver_links
         SET permission = #{manage}, updated_at = CURRENT_TIMESTAMP
       WHERE permission = #{view}
         AND caregiver_id IS NOT NULL
    SQL
  end

  # Deliberately irreversible. Rolling back would have to guess which links were
  # view because somebody chose that and which were view because the application
  # could not say otherwise — and it cannot, because nothing ever chose.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
