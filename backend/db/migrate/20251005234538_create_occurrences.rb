class CreateOccurrences < ActiveRecord::Migration[8.0]
  def change
    create_table :occurrences do |t|
      t.references :reminder, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end
    add_index :occurrences, [:reminder_id, :scheduled_at], unique: true
  end
end
