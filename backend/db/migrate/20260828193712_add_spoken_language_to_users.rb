# frozen_string_literal: true

class AddSpokenLanguageToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :spoken_language, :string, default: "en-US", null: false
  end
end
