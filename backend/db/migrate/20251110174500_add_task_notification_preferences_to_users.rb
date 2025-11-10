class AddTaskNotificationPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :notify_on_task_assigned_to_others, :boolean, default: false
  end
end
