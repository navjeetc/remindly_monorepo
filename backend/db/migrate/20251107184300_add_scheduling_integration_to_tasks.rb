class AddSchedulingIntegrationToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :scheduling_integration, foreign_key: true
    add_column :tasks, :external_source, :string
    add_column :tasks, :external_id, :string
    add_column :tasks, :external_url, :string
    add_column :tasks, :sync_metadata, :json, default: {}
    
    add_index :tasks, [:external_source, :external_id], unique: true, where: "external_source IS NOT NULL"
    add_index :tasks, :external_source
  end
end
