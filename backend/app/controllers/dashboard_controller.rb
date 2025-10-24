class DashboardController < WebController
  before_action :authenticate!
  before_action :check_role!, except: [:profile, :update_profile]
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
      
      # Get upcoming tasks (next 7 days) - visible to senior
      @upcoming_tasks = Task.where(senior_id: current_user.id)
        .where.not(status: :completed)
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
  
  # Show how-to page
  def how_to
  end
  
  # Show contact form
  def contact
  end
  
  # Submit contact form
  def submit_contact
    name = params[:name]
    email = params[:email]
    description = params[:description]
    
    if name.blank? || email.blank? || description.blank?
      flash[:alert] = "All fields are required"
      render :contact
      return
    end
    
    # Log the contact submission
    Rails.logger.info "📧 Contact form submission: name=#{name}, email=#{email}, message_length=#{description.length}"
    
    # Send email to admin
    begin
      ContactMailer.contact_form_submission(
        name: name,
        email: email,
        description: description
      ).deliver_now
      
      Rails.logger.info "✅ Contact form email sent successfully to admin"
      redirect_to dashboard_path, notice: "Thank you for contacting us! We'll get back to you soon."
    rescue => e
      Rails.logger.error "❌ Failed to send contact form email: #{e.message}"
      redirect_to dashboard_path, notice: "Thank you for contacting us! We'll get back to you soon."
    end
  end
  
  # Show profile page
  def profile
  end
  
  # Update profile
  def update_profile
    if current_user.update(profile_params)
      # Redirect back to dashboard (which will show pending_approval if no role)
      redirect_to dashboard_path, notice: "Profile updated successfully"
    else
      render :profile, status: :unprocessable_entity
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
  
  # Invite another caregiver to help with a senior
  def invite_caregiver
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
  end
  
  def process_invite_caregiver
    @senior_id = params[:senior_id]
    link = current_user.caregiver_links.find_by!(senior_id: @senior_id)
    @senior = link.senior
    
    caregiver_email = params[:caregiver_email]&.strip&.downcase
    
    if caregiver_email.blank?
      flash[:alert] = "Please enter a caregiver email"
      render :invite_caregiver
      return
    end
    
    # Find or create the caregiver user
    caregiver = User.find_by(email: caregiver_email)
    
    if caregiver.nil?
      # Create new user with caregiver role
      caregiver = User.create!(
        email: caregiver_email,
        role: :caregiver
      )
    elsif caregiver.id == @senior.id
      # Can't invite the senior to be their own caregiver
      flash[:alert] = "You cannot invite the senior to be their own caregiver"
      render :invite_caregiver
      return
    elsif !caregiver.role_caregiver?
      # Only caregivers can be invited
      flash[:alert] = "#{caregiver_email} must be a caregiver to be invited. They are currently a #{caregiver.role}."
      render :invite_caregiver
      return
    end
    
    # Check if already linked
    existing_link = CaregiverLink.find_by(senior_id: @senior.id, caregiver_id: caregiver.id)
    if existing_link
      flash[:alert] = "#{caregiver_email} is already linked to this senior"
      redirect_to senior_dashboard_path(@senior)
      return
    end
    
    # Create the link with view permission by default
    CaregiverLink.create!(
      senior_id: @senior.id,
      caregiver_id: caregiver.id,
      permission: :view
    )
    
    redirect_to senior_dashboard_path(@senior), notice: "Successfully invited #{caregiver_email} to help with #{@senior.email}"
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
  
  def profile_params
    params.require(:user).permit(:name, :nickname, :tz)
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
