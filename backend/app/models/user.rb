class User < ApplicationRecord
  enum :role, { senior: 0, caregiver: 1, admin: 2 }, prefix: true

  # Roles a user may choose for themselves — at onboarding, or later from their
  # profile. Admin is deliberately excluded: it is never self-granted, and this
  # path also refuses to touch an existing admin's role.
  SELF_ASSIGNABLE_ROLES = %w[senior caregiver].freeze

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

  # Scheduling integrations
  has_many :scheduling_integrations, dependent: :destroy

  # Notifications
  has_many :notifications, dependent: :destroy

  # Time blocks
  has_many :time_blocks, dependent: :destroy

  # Ahoy analytics
  has_many :visits, class_name: "Ahoy::Visit", dependent: :destroy
  has_many :events, class_name: "Ahoy::Event", dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, on: :update, if: -> { !new_record? }
  attribute :tz, :string, default: "America/New_York"

  # Class methods to get users by role
  def self.caregivers
    where(role: :caregiver)
  end

  def self.seniors
    where(role: :senior)
  end

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
    nickname.presence || name.presence || email.split("@").first
  end

  # Reminder categories this caregiver wants completion/miss notifications for.
  # Normalized on write: only real, deduped categories are stored, so a stray
  # value from the form is dropped. A category later removed from the enum is
  # cleaned from a user's stored set the next time they save preferences, not
  # retroactively — though a removed category would no longer match any reminder
  # anyway, so it can't produce a notification in the meantime.
  def notify_reminder_categories=(values)
    super(Array(values).map(&:to_s).select { |c| Reminder.categories.key?(c) }.uniq)
  end

  def notified_for?(category)
    notify_reminder_categories.include?(category.to_s)
  end

  # Let a user set their own role during onboarding or when switching later. Only
  # the non-privileged roles are allowed, and an existing admin can't be demoted
  # through here. update_column skips the name-presence-on-update validation — a
  # brand-new user has no name yet, and picking a role must not require one.
  def assign_self_role(new_role)
    return false if role_admin?
    return false unless SELF_ASSIGNABLE_ROLES.include?(new_role.to_s)

    update_column(:role, new_role.to_s)
  end
end
