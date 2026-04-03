class AddUniqueIndexToTasksParentAndScheduledAt < ActiveRecord::Migration[8.0]
  def change
    # Add unique constraint to prevent duplicate task instances for recurring tasks
    # This ensures find_or_create_by!(scheduled_at: scheduled_at) is safe under concurrency
    add_index :tasks, [:parent_task_id, :scheduled_at], 
              unique: true, 
              where: "parent_task_id IS NOT NULL",
              name: "index_tasks_on_parent_task_id_and_scheduled_at"
  end
end
