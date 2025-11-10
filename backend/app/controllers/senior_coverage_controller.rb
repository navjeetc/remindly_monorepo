class SeniorCoverageController < WebController
  before_action :authenticate!
  before_action :check_feature_enabled!
  before_action :require_caregiver!
  before_action :set_senior
  layout 'dashboard'

  # GET /seniors/:senior_id/coverage
  def show
    # Get all caregivers linked to this senior
    @caregiver_links = @senior.senior_links.includes(:caregiver)
    @caregivers = @caregiver_links.map(&:caregiver)
    
    # Get date range (default: current week)
    @start_date = params[:start_date]&.to_date || Date.current.beginning_of_week
    @end_date = @start_date + 6.days
    
    # Get all availability for this week for all caregivers
    @availabilities = CaregiverAvailability
      .where(caregiver_id: @caregivers.map(&:id))
      .in_date_range(@start_date, @end_date)
      .order(:date, :start_time)
      .includes(:caregiver)
    
    # Group by date and caregiver
    @availabilities_by_date = @availabilities.group_by(&:date)
    @availabilities_by_caregiver = @availabilities.group_by(&:caregiver_id)
    
    # Find coverage gaps (dates with no availability)
    @coverage_gaps = find_coverage_gaps
  end

  private

  def check_feature_enabled!
    unless FeatureFlag.enabled?(:native_scheduling)
      redirect_to dashboard_path, alert: "Native scheduling is not enabled"
    end
  end

  def require_caregiver!
    unless current_user.role_caregiver?
      redirect_to dashboard_path, alert: "Only caregivers can view coverage"
    end
  end

  def set_senior
    @senior = User.find(params[:senior_id])
    
    # Verify current user is linked to this senior
    link = current_user.caregiver_links.find_by(senior_id: @senior.id)
    unless link&.active?
      redirect_to dashboard_path, alert: "You don't have access to this senior's information"
    end
  end

  def find_coverage_gaps
    gaps = []
    (@start_date..@end_date).each do |date|
      # Skip if it's in the past
      next if date < Date.current
      
      # Check if any caregiver has availability on this date
      has_coverage = @availabilities_by_date[date].present?
      
      gaps << date unless has_coverage
    end
    gaps
  end
end
