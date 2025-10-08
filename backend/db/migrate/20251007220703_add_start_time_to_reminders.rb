class AddStartTimeToReminders < ActiveRecord::Migration[8.0]
  def change
    add_column :reminders, :start_time, :datetime
  end
end
