class CoverageGapNotificationService
  # Check for coverage gaps and notify caregivers
  # @param senior [User] The senior to check coverage for
  # @param start_date [Date] Start date for checking
  # @param end_date [Date] End date for checking (default: 2 weeks ahead)
  def self.check_and_notify(senior, start_date = Date.current, end_date = Date.current + 14.days)
    return unless senior.role_senior?
    
    caregivers = senior.caregivers.where.not(id: nil)
    return if caregivers.empty?
    
    # Find coverage gaps
    gaps = find_coverage_gaps(senior, start_date, end_date)
    
    if gaps.any?
      # Create in-app notifications for all caregivers
      caregivers.each do |caregiver|
        create_gap_notification(caregiver, senior, gaps)
      end
      
      # Send email notifications
      caregivers.each do |caregiver|
        CoverageGapMailer.notify_gap(
          caregiver: caregiver,
          senior: senior,
          gaps: gaps
        ).deliver_later
      end
    end
  end
  
  # Notify when a coverage gap is filled
  # @param senior [User] The senior
  # @param date [Date] The date that was filled
  def self.notify_gap_filled(senior, date)
    return unless senior.role_senior?
    
    caregivers = senior.caregivers.where.not(id: nil)
    return if caregivers.empty?
    
    caregivers.each do |caregiver|
      # Mark old gap notifications for this date as read (they're now outdated)
      Notification
        .where(user: caregiver, notification_type: Notification::TYPES[:coverage_gap])
        .unread
        .where("metadata->>'senior_id' = ?", senior.id.to_s)
        .where("metadata->'gap_dates' @> ?", [date.to_s].to_json)
        .update_all(read_at: Time.current)
      
      # Create new "gap filled" notification
      Notification.create!(
        user: caregiver,
        notification_type: Notification::TYPES[:coverage_filled],
        title: "Coverage filled for #{senior.display_name}",
        message: "#{date.strftime('%A, %B %d')} now has caregiver coverage.",
        metadata: {
          senior_id: senior.id,
          senior_name: senior.display_name,
          date: date.to_s
        }
      )
    end
  end
  
  private
  
  def self.find_coverage_gaps(senior, start_date, end_date)
    caregiver_ids = senior.caregivers.pluck(:id)
    
    gaps = []
    (start_date..end_date).each do |date|
      # Skip past dates
      next if date < Date.current
      
      # Check if any caregiver has availability on this date
      has_coverage = CaregiverAvailability
        .where(caregiver_id: caregiver_ids, date: date)
        .exists?
      
      gaps << date unless has_coverage
    end
    
    gaps
  end
  
  def self.create_gap_notification(caregiver, senior, gaps)
    # Don't create duplicate notifications for the same gaps
    existing = Notification
      .where(user: caregiver, notification_type: Notification::TYPES[:coverage_gap])
      .where("created_at > ?", 1.day.ago)
      .where("metadata->>'senior_id' = ?", senior.id.to_s)
      .exists?
    
    return if existing
    
    gap_dates = gaps.map { |d| d.strftime('%a, %b %d') }.join(', ')
    
    Notification.create!(
      user: caregiver,
      notification_type: Notification::TYPES[:coverage_gap],
      title: "Coverage gaps for #{senior.display_name}",
      message: "No caregiver availability on: #{gap_dates}",
      metadata: {
        senior_id: senior.id,
        senior_name: senior.display_name,
        gap_dates: gaps.map(&:to_s),
        gap_count: gaps.count
      }
    )
  end
end
