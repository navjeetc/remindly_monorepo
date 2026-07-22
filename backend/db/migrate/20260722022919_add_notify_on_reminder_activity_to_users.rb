class AddNotifyOnReminderActivityToUsers < ActiveRecord::Migration[8.1]
  def change
    # Per-caregiver notification preference, following the same boolean-column
    # pattern as notify_on_task_assigned_to_others — but defaulting ON, where that
    # one defaults off: caregivers hear about a senior's medication completions and
    # misses unless they deliberately turn it off.
    add_column :users, :notify_on_reminder_activity, :boolean, default: true, null: false
  end
end
