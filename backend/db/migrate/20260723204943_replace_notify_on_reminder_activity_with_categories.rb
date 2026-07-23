class ReplaceNotifyOnReminderActivityWithCategories < ActiveRecord::Migration[8.1]
  # The single notify_on_reminder_activity flag only ever gated the medication
  # category. Replace it with a set of chosen categories so each caregiver picks
  # what they hear about — stored as an array of category names rather than a
  # column per category, so adding a new Reminder category never needs a migration
  # or a schema change. Defaults preserve today's behavior: medication on by
  # default, and a caregiver who had turned the old flag off starts with none.
  def up
    add_column :users, :notify_reminder_categories, :json, default: [ "medication" ], null: false

    execute "UPDATE users SET notify_reminder_categories = '[\"medication\"]' WHERE notify_on_reminder_activity"
    execute "UPDATE users SET notify_reminder_categories = '[]' WHERE NOT notify_on_reminder_activity"

    remove_column :users, :notify_on_reminder_activity
  end

  def down
    add_column :users, :notify_on_reminder_activity, :boolean, default: true, null: false
    # Medication was the only category the old flag represented.
    execute "UPDATE users SET notify_on_reminder_activity = (instr(notify_reminder_categories, 'medication') > 0)"
    remove_column :users, :notify_reminder_categories
  end
end
