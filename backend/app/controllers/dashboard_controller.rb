class DashboardController < WebController
  before_action :authenticate!
  before_action :check_role!
  layout 'dashboard'
  
  # Landing page - show pairing or dashboard
  def index
    Rails.logger.info "🔍 Dashboard index: user_id=#{current_user.id}, role=#{current_user.role}, role_senior?=#{current_user.role_senior?}"
    
    # Redirect admins to admin panel
    if current_user.role_admin?
      redirect_to admin_users_path
      return
    end
    
    # Only show relevant data based on role
    if current_user.role_caregiver?
      # Caregivers only see seniors they're caring for
      @linked_seniors = current_user.caregiver_links
        .includes(:senior)
        .where.not(senior_id: nil)
      @pending_links = []
    elsif current_user.role_senior?
      # Seniors see their own tasks, reminders, and caregivers
      @linked_seniors = []
      @pending_links = current_user.senior_links.where(caregiver_id: nil).where.not(pairing_token: nil)
      
      # Get today's reminders for the senior
      tz = ActiveSupport::TimeZone[current_user.tz]
      now = tz.now.beginning_of_day
      end_of_day = now.end_of_day
      
      # Expand all reminders to ensure today's occurrences exist
      current_user.reminders.each do |reminder|
        Recurrence.expand(reminder)
      end
      
      @today_occurrences = Occurrence.joins(:reminder)
        .where(reminders: { user_id: current_user.id }, scheduled_at: now..end_of_day)
        .order(:scheduled_at)
        .includes(:reminder, :acknowledgements)
      
      # Get upcoming tasks (next 7 days) - only assigned and visible to senior
      @upcoming_tasks = Task.where(senior_id: current_user.id)
        .where.not(status: :completed)
        .where.not(assigned_to_id: nil)
        .where(visible_to_senior: true)
        .where('scheduled_at >= ?', now)
        .where('scheduled_at <= ?', now + 7.days)
        .order(:scheduled_at)
        .limit(10)
      
      Rails.logger.info "📋 Senior dashboard: user_id=#{current_user.id}, tasks=#{@upcoming_tasks.count}, occurrences=#{@today_occurrences.count}"
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
    redirect_to dashboard_path, alert: "Access denied"
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
    
    # Get sanitized params
    permitted = reminder_params
    
    # Build rrule from form params
    time = permitted[:time] || Time.current.strftime("%H:%M")
    frequency = permitted[:frequency] || "DAILY"
    
    # Parse time with validation
    tz = ActiveSupport::TimeZone[@senior.tz]
    start_time = parse_time_safely(time, tz)
    
    unless start_time
      @reminder = @senior.reminders.build(permitted)
      @reminder.errors.add(:base, "Invalid time format. Please use HH:MM format (00:00 - 23:59)")
      render :new_reminder
      return
    end
    
    # Build rrule
    rrule = "FREQ=#{frequency.upcase}"
    
    @reminder = @senior.reminders.build(
      title: permitted[:title],
      notes: permitted[:notes],
      category: permitted[:category] || :routine,
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
    redirect_to dashboard_path, alert: "Access denied"
  end
  
  # Update reminder
  def update_reminder
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    @reminder = @senior.reminders.find(params[:reminder_id])
    
    # Get sanitized params
    permitted = reminder_params
    
    # Build rrule from form params
    time = permitted[:time] || Time.current.strftime("%H:%M")
    frequency = permitted[:frequency] || "DAILY"
    
    # Parse time with validation
    tz = ActiveSupport::TimeZone[@senior.tz]
    start_time = parse_time_safely(time, tz)
    
    unless start_time
      @reminder.errors.add(:base, "Invalid time format. Please use HH:MM format (00:00 - 23:59)")
      render :edit_reminder
      return
    end
    
    # Build rrule
    rrule = "FREQ=#{frequency.upcase}"
    
    if @reminder.update(
      title: permitted[:title],
      notes: permitted[:notes],
      category: permitted[:category] || :routine,
      rrule: rrule,
      start_time: start_time
    )
      # Delete all pending occurrences and regenerate
      # This ensures the new time/schedule applies immediately
      @reminder.occurrences.where(status: :pending).destroy_all
      Recurrence.expand(@reminder)
      redirect_to senior_dashboard_path(@senior), notice: "Reminder updated successfully!"
    else
      render :edit_reminder
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_path, alert: "Access denied"
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
    redirect_to dashboard_path, alert: "Access denied"
  end
  
  private
  
  def check_role!
    if current_user.role.nil?
      render 'pending_approval', layout: 'dashboard'
    end
  end
  
  def reminder_params
    params.require(:reminder).permit(:title, :notes, :category, :time, :frequency)
  end
  
  def parse_time_safely(time_string, timezone)
    # Validate time format (HH:MM)
    unless time_string.match?(/\A\d{1,2}:\d{2}\z/)
      return nil
    end
    
    hour, minute = time_string.split(":").map(&:to_i)
    
    # Validate ranges
    return nil unless (0..23).cover?(hour) && (0..59).cover?(minute)
    
    timezone.now.change(hour: hour, min: minute, sec: 0)
  end
end
