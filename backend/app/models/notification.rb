class Notification < ApplicationRecord
  belongs_to :user

  # Notification types
  TYPES = {
    coverage_gap: 'coverage_gap',
    coverage_filled: 'coverage_filled',
    availability_changed: 'availability_changed'
  }.freeze

  validates :notification_type, presence: true, inclusion: { in: TYPES.values }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_type, ->(type) { where(notification_type: type) }

  # Mark notification as read
  def mark_as_read!
    update(read_at: Time.current) unless read?
  end

  # Check if notification is read
  def read?
    read_at.present?
  end

  # Check if notification is unread
  def unread?
    !read?
  end
end
