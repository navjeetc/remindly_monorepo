class AddRecurrenceToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :rrule, :string
    add_column :tasks, :tz, :string
    add_column :tasks, :start_time, :datetime
    add_reference :tasks, :parent_task, foreign_key: { to_table: :tasks }
    
    add_index :tasks, :rrule
  end
end
