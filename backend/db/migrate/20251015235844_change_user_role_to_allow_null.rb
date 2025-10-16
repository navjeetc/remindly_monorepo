class ChangeUserRoleToAllowNull < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :role, true
    change_column_default :users, :role, from: 0, to: nil
  end
end
