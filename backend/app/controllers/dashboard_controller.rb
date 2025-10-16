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
  
  # New reminder form for senior
  def new_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @reminder = Reminder.new
  end
  
  # Edit reminder form
  def edit_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @reminder = @senior.reminders.find(params[:reminder_id])
  end
  
  # Create reminder for senior
  def create_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    
    # Build rrule from form params
    time = params[:reminder][:time] || Time.current.strftime("%H:%M")
    frequency = params[:reminder][:frequency] || "DAILY"
    
    # Parse time and create start_time in senior's timezone
    tz = ActiveSupport::TimeZone[@senior.tz]
    hour, minute = time.split(":").map(&:to_i)
    start_time = tz.now.change(hour: hour, min: minute, sec: 0)
    
    # Build rrule
    rrule = "FREQ=#{frequency.upcase}"
    
    @reminder = @senior.reminders.build(
      title: params[:reminder][:title],
      notes: params[:reminder][:notes],
      category: params[:reminder][:category] || :routine,
      rrule: rrule,
      tz: @senior.tz,
      start_time: start_time
    )
    
    if @reminder.save
      # Generate occurrences for the reminder
      Recurrence.expand(@reminder)
      redirect_to senior_dashboard_path(@senior), notice: "Reminder created successfully!"
    else
      render :new_reminder
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Senior not found or not linked"
  end
  
  # Update reminder
  def update_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @reminder = @senior.reminders.find(params[:reminder_id])
    
    # Build rrule from form params
    time = params[:reminder][:time] || Time.current.strftime("%H:%M")
    frequency = params[:reminder][:frequency] || "DAILY"
    
    # Parse time and create start_time in senior's timezone
    tz = ActiveSupport::TimeZone[@senior.tz]
    hour, minute = time.split(":").map(&:to_i)
    start_time = tz.now.change(hour: hour, min: minute, sec: 0)
    
    # Build rrule
    rrule = "FREQ=#{frequency.upcase}"
    
    if @reminder.update(
      title: params[:reminder][:title],
      notes: params[:reminder][:notes],
      category: params[:reminder][:category] || :routine,
      rrule: rrule,
      start_time: start_time
    )
      # Don't delete any occurrences - just update the reminder
      # Existing occurrences will keep the old schedule
      # New occurrences will be created with the new schedule
      Recurrence.expand(@reminder)
      redirect_to senior_dashboard_path(@senior), notice: "Reminder updated successfully! Changes will apply to future reminders."
    else
      render :edit_reminder
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Reminder or senior not found"
  end
  
  # Delete reminder
  def delete_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @reminder = @senior.reminders.find(params[:reminder_id])
    
    @reminder.destroy!
    redirect_to senior_dashboard_path(@senior), notice: "Reminder deleted successfully!"
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Reminder or senior not found"
  end
  
  private
  
  def check_role!
    if current_user.role.nil?
      render 'pending_approval', layout: 'dashboard'
    end
  end
  
  def reminder_params
    params.require(:reminder).permit(:title, :notes, :category, :time_of_day, :frequency, :days_of_week)
  end
end
