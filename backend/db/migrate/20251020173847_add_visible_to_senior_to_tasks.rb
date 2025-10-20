class AddVisibleToSeniorToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :visible_to_senior, :boolean, default: true, null: false
  end
end
