class CreateAcknowledgements < ActiveRecord::Migration[8.0]
  def change
    create_table :acknowledgements do |t|
      t.references :occurrence, null: false, foreign_key: true
      t.integer :kind, null: false
      t.datetime :at, null: false
      t.timestamps
    end
  end
end
