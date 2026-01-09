class MakeScheduledAtOptionalInTasks < ActiveRecord::Migration[8.0]
  def change
    change_column_null :tasks, :scheduled_at, true
  end
end
