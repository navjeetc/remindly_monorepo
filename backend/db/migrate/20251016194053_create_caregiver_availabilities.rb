class CreateCaregiverAvailabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :caregiver_availabilities do |t|
      t.references :caregiver, null: false, foreign_key: { to_table: :users }
      t.date :date, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.text :notes

      t.timestamps
    end

    add_index :caregiver_availabilities, [:caregiver_id, :date]
    add_index :caregiver_availabilities, :date
  end
end
