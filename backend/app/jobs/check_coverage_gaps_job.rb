class CheckCoverageGapsJob < ApplicationJob
  queue_as :default

  # Check all seniors for coverage gaps and notify caregivers
  def perform
    Rails.logger.info "🔍 Checking coverage gaps..."
    
    # Get all seniors who have multiple caregivers
    seniors_with_caregivers = User.where(role: :senior)
      .joins(:senior_links)
      .where.not(caregiver_links: { caregiver_id: nil })
      .group('users.id')
      .having('COUNT(caregiver_links.id) > 0')
      .distinct
    
    seniors_with_caregivers.each do |senior|
      begin
        # Check next 2 weeks for gaps
        CoverageGapNotificationService.check_and_notify(
          senior,
          Date.current,
          Date.current + 14.days
        )
      rescue => e
        Rails.logger.error "Failed to check coverage for senior #{senior.id}: #{e.message}"
      end
    end
    
    Rails.logger.info "✅ Coverage gap check complete"
  end
end
