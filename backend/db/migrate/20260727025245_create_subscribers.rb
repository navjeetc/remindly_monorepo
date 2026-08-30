# frozen_string_literal: true

class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      # Stored already downcased and stripped by the model, so the unique index
      # below is genuinely unique rather than unique-per-capitalisation.
      t.string :email, null: false

      # Which page the address came from. The whole point of the list is finding
      # out which writing actually earns an address, and that is unrecoverable
      # after the fact.
      t.string :source

      t.timestamps
    end

    add_index :subscribers, :email, unique: true
  end
end
