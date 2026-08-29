class AddCriticalToReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :reminders, :critical, :boolean, default: false, null: false
  end
end
