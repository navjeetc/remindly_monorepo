class CreateCaregiverLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :caregiver_links do |t|
      t.integer :senior_id, null: false
      t.integer :caregiver_id, null: false
      t.timestamps
    end
    add_foreign_key :caregiver_links, :users, column: :senior_id
    add_foreign_key :caregiver_links, :users, column: :caregiver_id
    add_index :caregiver_links, [:senior_id, :caregiver_id], unique: true
  end
end
