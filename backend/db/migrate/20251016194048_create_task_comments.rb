class CreateTaskComments < ActiveRecord::Migration[8.0]
  def change
    create_table :task_comments do |t|
      t.references :task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end

    add_index :task_comments, [:task_id, :created_at]
  end
end
