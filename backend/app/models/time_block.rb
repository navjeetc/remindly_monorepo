class TimeBlock < ApplicationRecord
  belongs_to :user

  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time
  validate :no_overlapping_blocks

  scope :active, -> { where(active: true) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :recurring, -> { where(recurring: true) }
  scope :one_time, -> { where(recurring: false) }
  scope :overlapping, ->(start_time, end_time) {
    where("start_time < ? AND end_time > ?", end_time, start_time)
  }

  # Check if a given time falls within this block
  def blocks_time?(time)
    return false unless active?
    time >= start_time && time < end_time
  end

  # Check if a time range overlaps with this block
  def blocks_range?(range_start, range_end)
    return false unless active?
    # Ranges overlap if one starts before the other ends
    range_start < end_time && range_end > start_time
  end

  # Human-readable description
  def description
    if recurring?
      pattern_desc = recurrence_pattern || "recurring"
      "#{reason || 'Blocked time'} (#{pattern_desc})"
    else
      "#{reason || 'Blocked time'} on #{start_time.strftime('%b %d, %Y')}"
    end
  end

  private

  def end_time_after_start_time
    return if end_time.blank? || start_time.blank?
    
    if end_time <= start_time
      errors.add(:end_time, "must be after start time")
    end
  end

  def no_overlapping_blocks
    return if start_time.blank? || end_time.blank?
    
    overlapping = TimeBlock.active
      .where(user_id: user_id)
      .where.not(id: id)
      .overlapping(start_time, end_time)
    
    if overlapping.exists?
      errors.add(:base, "This time block overlaps with an existing block")
    end
  end
end
