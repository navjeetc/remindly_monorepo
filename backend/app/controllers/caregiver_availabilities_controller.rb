class CaregiverAvailabilitiesController < WebController
  before_action :authenticate!
  before_action :check_feature_enabled!
  before_action :require_caregiver!
  before_action :set_availability, only: [:edit, :update, :destroy]
  layout 'dashboard'

  # GET /caregiver_availabilities
  def index
    @availabilities = current_user.caregiver_availabilities
                                  .order(:date, :start_time)
    
    # Group by date for display
    @availabilities_by_date = @availabilities.group_by(&:date)
  end

  # GET /caregiver_availabilities/new
  def new
    @availability = current_user.caregiver_availabilities.build
  end

  # GET /caregiver_availabilities/bulk_new
  def bulk_new
    @start_date = params[:start_date]&.to_date || Date.current
    # Prevent going back before today
    @start_date = Date.current if @start_date < Date.current
  end

  # POST /caregiver_availabilities
  def create
    @availability = current_user.caregiver_availabilities.build(availability_params)

    if @availability.save
      redirect_to caregiver_availabilities_path, notice: "Availability added successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # POST /caregiver_availabilities/bulk_create
  def bulk_create
    dates = parse_bulk_dates(params[:dates])
    start_time = params[:start_time]
    end_time = params[:end_time]
    notes = params[:notes]

    if dates.empty?
      redirect_to bulk_new_caregiver_availabilities_path, alert: "Please select at least one date"
      return
    end

    availabilities = CaregiverAvailability.create_bulk(
      caregiver: current_user,
      dates: dates,
      start_time: start_time,
      end_time: end_time,
      notes: notes
    )

    successful = availabilities.select(&:persisted?)
    failed = availabilities.reject(&:persisted?)

    if failed.empty?
      redirect_to caregiver_availabilities_path, notice: "Added availability for #{successful.count} days"
    else
      redirect_to bulk_new_caregiver_availabilities_path, 
                  alert: "Added #{successful.count} days, but #{failed.count} failed (check for overlaps or past dates)"
    end
  end

  # GET /caregiver_availabilities/:id/edit
  def edit
  end

  # PATCH /caregiver_availabilities/:id
  def update
    if @availability.update(availability_params)
      redirect_to caregiver_availabilities_path, notice: "Availability updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /caregiver_availabilities/:id
  def destroy
    @availability.destroy
    redirect_to caregiver_availabilities_path, notice: "Availability removed successfully"
  end

  private

  def check_feature_enabled!
    unless FeatureFlag.enabled?(:native_scheduling)
      redirect_to dashboard_path, alert: "Native scheduling is not enabled"
    end
  end

  def require_caregiver!
    unless current_user.role_caregiver?
      redirect_to dashboard_path, alert: "Only caregivers can manage availability"
    end
  end

  def set_availability
    @availability = current_user.caregiver_availabilities.find(params[:id])
  end

  def availability_params
    params.require(:caregiver_availability).permit(
      :date,
      :start_time,
      :end_time,
      :notes
    )
  end

  def parse_bulk_dates(dates_param)
    return [] if dates_param.blank?
    
    # dates_param can be an array of date strings or a comma-separated string
    if dates_param.is_a?(Array)
      dates_param.map { |d| Date.parse(d) rescue nil }.compact
    else
      dates_param.split(',').map { |d| Date.parse(d.strip) rescue nil }.compact
    end
  end
end
