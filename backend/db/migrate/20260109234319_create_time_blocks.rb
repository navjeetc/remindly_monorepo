class CreateTimeBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :time_blocks do |t|
      t.references :user, null: false, foreign_key: true
      t.datetime :start_time, null: false
      t.datetime :end_time, null: false
      t.string :reason
      t.boolean :recurring, default: false, null: false
      t.string :recurrence_pattern
      t.boolean :active, default: true, null: false

      t.timestamps
    end
    
    add_index :time_blocks, [:user_id, :start_time, :end_time]
    add_index :time_blocks, :active
  end
end
