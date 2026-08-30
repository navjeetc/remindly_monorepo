# frozen_string_literal: true

class CreateTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :telnyx_calls do |t|
      t.string :call_control_id, null: false
      t.string :call_leg_id
      t.references :occurrence, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :outcome, null: false, default: "pending"
      t.string :dtmf
      t.text :last_payload
      t.datetime :answered_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :telnyx_calls, :call_control_id, unique: true
    add_index :telnyx_calls, :call_leg_id, unique: true, where: "call_leg_id IS NOT NULL"
  end
end
