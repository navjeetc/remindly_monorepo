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

  # POST /caregiver_availabilities
  def create
    @availability = current_user.caregiver_availabilities.build(availability_params)

    if @availability.save
      redirect_to caregiver_availabilities_path, notice: "Availability added successfully"
    else
      render :new, status: :unprocessable_entity
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
end
