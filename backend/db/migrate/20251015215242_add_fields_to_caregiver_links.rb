class AddFieldsToCaregiverLinks < ActiveRecord::Migration[8.0]
  def change
    add_column :caregiver_links, :permission, :integer, default: 0, null: false
    add_column :caregiver_links, :pairing_token, :string
    add_index :caregiver_links, :pairing_token, unique: true
  end
end
