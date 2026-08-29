class Notification < ApplicationRecord
  belongs_to :user

  # Notification types
  TYPES = {
    coverage_gap: "coverage_gap",
    coverage_filled: "coverage_filled",
    availability_changed: "availability_changed",
    task_available: "task_available",
    task_assigned: "task_assigned",
    reminder_acknowledged: "reminder_acknowledged",
    reminder_missed: "reminder_missed",
    # A call for a critical reminder went unanswered. Distinct from
    # reminder_missed on purpose: it says "she has not picked up yet", not "the
    # dose was missed" — more calls usually follow, and the message says how
    # many, which is not always more than none. Sharing the type
    # would also let the unique index swallow the later missed alert, which is
    # the one that means the dose really did not happen.
    reminder_unanswered: "reminder_unanswered"
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
