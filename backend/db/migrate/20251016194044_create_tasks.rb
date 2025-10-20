class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.references :senior, null: false, foreign_key: { to_table: :users }
      t.references :assigned_to, foreign_key: { to_table: :users }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.integer :task_type, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.datetime :scheduled_at, null: false
      t.integer :duration_minutes
      t.string :location
      t.text :notes
      t.datetime :completed_at

      t.timestamps
    end

    add_index :tasks, :task_type
    add_index :tasks, :status
    add_index :tasks, :scheduled_at
    add_index :tasks, [:senior_id, :scheduled_at]
    add_index :tasks, [:assigned_to_id, :status]
  end
end
