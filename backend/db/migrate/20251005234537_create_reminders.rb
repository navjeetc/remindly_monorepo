class CreateReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.string :rrule, null: false
      t.string :tz, null: false
      t.integer :category, default: 0
      t.timestamps
    end
  end
end
