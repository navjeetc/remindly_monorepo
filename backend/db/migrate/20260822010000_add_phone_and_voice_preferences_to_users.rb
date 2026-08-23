class AddPhoneAndVoicePreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone, :string
    add_column :users, :voice_reminders_enabled, :boolean, default: false, null: false
  end
end
