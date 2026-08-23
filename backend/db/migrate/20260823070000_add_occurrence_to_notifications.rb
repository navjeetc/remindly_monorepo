# Makes "already notified about this occurrence" a constraint instead of a race.
#
# ReminderNotificationService checked with a SELECT and then created the row, so
# two workers handling redelivered webhooks could both pass the check and each
# create an alert and send an email. The occurrence id lived only inside the
# json metadata column, where nothing can be indexed, so the check had no way to
# be atomic.
#
# The column is nullable and the index partial because not every notification is
# about an occurrence — coverage_gap and coverage_filled are about a date.
class AddOccurrenceToNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :notifications, :occurrence_id, :integer

    # Backfill from metadata so existing rows participate in the constraint
    # rather than being invisible to it.
    execute <<~SQL
      UPDATE notifications
         SET occurrence_id = CAST(json_extract(metadata, '$.occurrence_id') AS INTEGER)
       WHERE json_valid(metadata)
         AND json_extract(metadata, '$.occurrence_id') IS NOT NULL
    SQL

    # Collapse any duplicates the old non-atomic check already let through,
    # keeping the earliest of each set. Production had none when this was
    # written, but the entrypoint runs db:prepare at container start, so a
    # unique index that raises does not fail here — it aborts the boot and
    # blocks the deploy.
    execute <<~SQL
      DELETE FROM notifications
       WHERE occurrence_id IS NOT NULL
         AND id NOT IN (
           SELECT MIN(id) FROM notifications
            WHERE occurrence_id IS NOT NULL
            GROUP BY user_id, notification_type, occurrence_id
         )
    SQL

    add_index :notifications, [ :user_id, :notification_type, :occurrence_id ],
              unique: true, where: "occurrence_id IS NOT NULL",
              name: "index_notifications_on_user_type_and_occurrence"
  end

  def down
    remove_index :notifications, name: "index_notifications_on_user_type_and_occurrence"
    remove_column :notifications, :occurrence_id
  end
end
