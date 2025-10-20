class TaskComment < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :content, presence: true, length: { minimum: 1, maximum: 5000 }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_task, ->(task_id) { where(task_id: task_id) }
end
