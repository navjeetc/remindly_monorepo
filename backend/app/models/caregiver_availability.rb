class CaregiverAvailability < ApplicationRecord
  belongs_to :caregiver, class_name: "User"

  validates :date, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time

  # Scopes
  scope :for_caregiver, ->(caregiver_id) { where(caregiver_id: caregiver_id) }
  scope :for_date, ->(date) { where(date: date) }
  scope :in_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :upcoming, -> { where("date >= ?", Date.current).order(:date, :start_time) }

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end
end
