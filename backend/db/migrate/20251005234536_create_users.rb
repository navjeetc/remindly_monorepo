class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.integer :role, default: 0, null: false
      t.string :tz, default: "America/New_York"
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
