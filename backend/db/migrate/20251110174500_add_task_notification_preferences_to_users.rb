class AddTaskNotificationPreferencesToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :notify_on_task_assigned_to_others, :boolean, default: false
  end
end
