class CaregiverAvailability < ApplicationRecord
  belongs_to :caregiver, class_name: "User"

  validates :date, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time
  validate :date_not_in_past
  validate :no_overlapping_availability

  # Scopes
  scope :for_caregiver, ->(caregiver_id) { where(caregiver_id: caregiver_id) }
  scope :for_date, ->(date) { where(date: date) }
  scope :in_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }
  scope :upcoming, -> { where("date >= ?", Date.current).order(:date, :start_time) }
  scope :past, -> { where("date < ?", Date.current).order(date: :desc, start_time: :desc) }

  # Create multiple availability entries at once
  # @param caregiver [User] The caregiver
  # @param dates [Array<Date>] Array of dates
  # @param start_time [Time] Start time
  # @param end_time [Time] End time
  # @param notes [String] Optional notes
  # @return [Array<CaregiverAvailability>] Created availabilities
  def self.create_bulk(caregiver:, dates:, start_time:, end_time:, notes: nil)
    dates.map do |date|
      create(
        caregiver: caregiver,
        date: date,
        start_time: start_time,
        end_time: end_time,
        notes: notes
      )
    end
  end

  # Get available time slots for a specific date
  # @param caregiver_id [Integer] Caregiver ID
  # @param date [Date] Date to check
  # @return [Array<Hash>] Available time slots
  def self.available_slots_for_date(caregiver_id, date)
    for_caregiver(caregiver_id)
      .for_date(date)
      .order(:start_time)
      .map { |a| { start_time: a.start_time, end_time: a.end_time, id: a.id } }
  end

  # Check if caregiver is available at a specific time
  # @param caregiver_id [Integer] Caregiver ID
  # @param datetime [DateTime] DateTime to check
  # @param duration_minutes [Integer] Duration in minutes
  # @return [Boolean] True if available
  def self.available_at?(caregiver_id, datetime, duration_minutes = 60)
    date = datetime.to_date
    time = datetime.to_time
    end_time = time + duration_minutes.minutes

    for_caregiver(caregiver_id)
      .for_date(date)
      .where("start_time <= ? AND end_time >= ?", time, end_time)
      .exists?
  end

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end

  def date_not_in_past
    return if date.blank?

    if date < Date.current
      errors.add(:date, "cannot be in the past")
    end
  end

  def no_overlapping_availability
    return if date.blank? || start_time.blank? || end_time.blank?

    overlapping = CaregiverAvailability
      .where(caregiver_id: caregiver_id, date: date)
      .where.not(id: id) # Exclude self when updating
      .where("(start_time < ? AND end_time > ?) OR (start_time < ? AND end_time > ?) OR (start_time >= ? AND end_time <= ?)",
             end_time, start_time, start_time, end_time, start_time, end_time)

    if overlapping.exists?
      errors.add(:base, "This time slot overlaps with existing availability")
    end
  end
end
