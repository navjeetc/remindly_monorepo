class DashboardController < WebController
  before_action :authenticate!
  before_action :check_role!
  layout 'dashboard'
  
  # Landing page - show pairing or dashboard
  def index
    # Redirect admins to admin panel
    if current_user.role_admin?
      redirect_to admin_users_path
      return
    end
    
    # Only show relevant data based on role
    if current_user.role_caregiver?
      # Caregivers only see seniors they're caring for (exclude themselves)
      @linked_seniors = current_user.caregiver_links
        .includes(:senior)
        .where.not(senior_id: nil)
        .where.not(senior_id: current_user.id)
      @pending_links = []
    elsif current_user.role_senior?
      # Seniors see their caregivers and pending tokens
      @linked_seniors = []
      @pending_links = current_user.senior_links.where(caregiver_id: nil).where.not(pairing_token: nil)
    else
      # No role - will be caught by check_role!
      @linked_seniors = []
      @pending_links = []
    end
  end
  
  # Show pairing form
  def pair
  end
  
  # Process pairing
  def process_pair
    token = params[:token]
    link = CaregiverLink.find_by(pairing_token: token)
    
    if link&.pending?
      link.pair_with(caregiver: current_user)
      redirect_to dashboard_path, notice: "Successfully paired with #{link.senior.email}"
    else
      redirect_to pair_dashboard_path, alert: "Invalid or expired pairing token"
    end
  end
  
  # Generate pairing token for senior
  def generate_token
    link = current_user.generate_pairing_token
    @pairing_token = link.pairing_token
    @expires_at = link.created_at + 7.days
  end
  
  # View senior's activity
  def senior
    @senior_id = params[:id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @permission = link.permission
    
    # Get today's reminders
    tz = ActiveSupport::TimeZone[@senior.tz]
    now = tz.now.beginning_of_day
    end_of_day = now.end_of_day
    
    @today_occurrences = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, scheduled_at: now..end_of_day)
      .order(:scheduled_at)
      .includes(:reminder, :acknowledgements)
    
    # Get 7-day activity
    start_date = now - 6.days
    @activity = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, scheduled_at: start_date..end_of_day)
      .order(scheduled_at: :desc)
      .includes(:reminder, :acknowledgements)
    
    # Get missed count
    @missed_count = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, status: :missed)
      .where('scheduled_at >= ?', 7.days.ago)
      .count
      
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Senior not found or not linked"
  end
  
  # Remove a link
  def unlink
    link = current_user.caregiver_links.find(params[:id])
    senior_email = link.senior.email
    link.destroy!
    redirect_to dashboard_path, notice: "Unlinked from #{senior_email}"
  end
  
  private
  
  def check_role!
    if current_user.role.nil?
      render 'pending_approval', layout: 'dashboard'
    end
  end
end
