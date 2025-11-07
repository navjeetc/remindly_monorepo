class CreateSchedulingIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduling_integrations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :senior, foreign_key: { to_table: :users }
      t.integer :provider, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string :provider_user_id, null: false
      t.string :api_key
      t.string :api_secret
      t.string :access_token
      t.string :webhook_secret
      t.datetime :last_synced_at
      t.boolean :sync_enabled, null: false, default: true
      t.json :settings, default: {}

      t.timestamps
    end

    add_index :scheduling_integrations, :provider
    add_index :scheduling_integrations, :status
    add_index :scheduling_integrations, [:user_id, :provider]
    add_index :scheduling_integrations, [:senior_id, :provider]
  end
end
