class Task < ApplicationRecord
  belongs_to :senior, class_name: "User"
  belongs_to :assigned_to, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :scheduling_integration, optional: true
  has_many :task_comments, dependent: :destroy

  enum :task_type, {
    appointment: 0,      # Doctor, dentist, specialist
    errand: 1,          # Grocery, pharmacy, shopping
    activity: 2,        # Social event, exercise class
    household: 3,       # Cleaning, maintenance
    transportation: 4,  # Ride to location
    other: 5
  }

  enum :status, {
    pending: 0,
    assigned: 1,
    in_progress: 2,
    completed: 3,
    cancelled: 4
  }

  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }

  validates :title, presence: true, length: { maximum: 255 }
  validates :task_type, presence: true
  validates :status, presence: true
  validates :priority, presence: true
  validates :scheduled_at, presence: true
  validates :duration_minutes, numericality: { greater_than: 0, allow_nil: true }

  # Scopes for common queries
  scope :upcoming, -> { where("scheduled_at >= ?", Time.current).order(:scheduled_at) }
  scope :past, -> { where("scheduled_at < ?", Time.current).order(scheduled_at: :desc) }
  scope :for_senior, ->(senior_id) { where(senior_id: senior_id) }
  scope :assigned_to_user, ->(user_id) { where(assigned_to_id: user_id) }
  scope :unassigned, -> { where(assigned_to_id: nil) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_type, ->(task_type) { where(task_type: task_type) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :in_date_range, ->(start_date, end_date) { where(scheduled_at: start_date..end_date) }
  
  # Scopes for external scheduling integrations
  scope :synced_from_external, -> { where.not(external_source: nil) }
  scope :manually_created, -> { where(external_source: nil) }
  scope :from_acuity, -> { where(external_source: 'acuity') }
  scope :from_calendly, -> { where(external_source: 'calendly') }

  # Callbacks
  before_save :update_status_on_assignment
  before_save :set_completed_at

  # Check if task is synced from external scheduling platform
  def external_appointment?
    external_source.present?
  end

  # Get link to view appointment in external system
  def external_link
    return nil unless external_appointment?
    
    case external_source
    when 'acuity'
      "https://secure.acuityscheduling.com/appointments/#{external_id}"
    when 'calendly'
      external_url
    else
      external_url
    end
  end

  # Get provider name for display
  def external_provider_name
    return nil unless external_appointment?
    external_source.titleize
  end

  private

  def update_status_on_assignment
    if assigned_to_id_changed? && assigned_to_id.present? && status == "pending"
      self.status = :assigned
    end
  end

  def set_completed_at
    if status_changed? && status == "completed" && completed_at.nil?
      self.completed_at = Time.current
    elsif status_changed? && status != "completed"
      self.completed_at = nil
    end
  end
end
