# frozen_string_literal: true

class AddTextSizeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :text_size, :integer, default: 0, null: false
  end
end
