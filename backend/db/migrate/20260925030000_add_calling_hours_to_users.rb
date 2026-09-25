# Calling hours per care receiver, replacing the one window every household
# shared. The defaults are that window, so nobody's calls move until a caregiver
# changes them. End is exclusive: 21 means the last call may start at 8:59pm.
class AddCallingHoursToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :calling_hours_start, :integer, null: false, default: 8
    add_column :users, :calling_hours_end, :integer, null: false, default: 21
  end
end
