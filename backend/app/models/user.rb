class User < ApplicationRecord
  enum :role, { senior: 0, caregiver: 1, admin: 2 }, prefix: true
  
  has_many :reminders, dependent: :destroy
  
  # Caregiver relationships
  has_many :senior_links, class_name: "CaregiverLink", foreign_key: "senior_id", dependent: :destroy
  has_many :caregivers, through: :senior_links, source: :caregiver
  
  has_many :caregiver_links, class_name: "CaregiverLink", foreign_key: "caregiver_id", dependent: :destroy
  has_many :seniors, through: :caregiver_links, source: :senior
  
  # Task relationships
  has_many :tasks_as_senior, class_name: "Task", foreign_key: "senior_id", dependent: :destroy
  has_many :assigned_tasks, class_name: "Task", foreign_key: "assigned_to_id", dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: "created_by_id", dependent: :nullify
  has_many :task_comments, dependent: :destroy
  has_many :caregiver_availabilities, foreign_key: "caregiver_id", dependent: :destroy
  
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, on: :update, if: -> { !new_record? }
  attribute :tz, :string, default: "America/New_York"
  
  # Generate a pairing token for this senior
  def generate_pairing_token
    CaregiverLink.generate_pairing_token(senior: self)
  end
  
  # Display name - uses nickname if available, otherwise name, otherwise email
  def display_name
    nickname.presence || name.presence || email
  end
  
  # Friendly name for seniors to recognize caregivers
  def friendly_name
    nickname.presence || name.presence || email.split('@').first
  end
end
