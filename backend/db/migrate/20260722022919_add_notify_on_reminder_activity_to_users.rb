class AddNotifyOnReminderActivityToUsers < ActiveRecord::Migration[8.1]
  def change
    # Opt-in defaulting on: caregivers hear about a senior's medication
    # completions and misses unless they turn it off, mirroring
    # notify_on_task_assigned_to_others.
    add_column :users, :notify_on_reminder_activity, :boolean, default: true, null: false
  end
end
