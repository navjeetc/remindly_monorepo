class SchedulingIntegrationsController < WebController
  before_action :authenticate!
  before_action :set_senior, only: [:index, :new, :create]
  before_action :authorize_senior_access!, only: [:index, :new, :create]
  before_action :set_integration, only: [:show, :edit, :update, :destroy, :sync]
  layout 'dashboard'

  # GET /dashboard/senior/:senior_id/scheduling_integrations
  def index
    @integrations = current_user.scheduling_integrations.includes(:senior)
    @senior_integrations = @senior ? @integrations.where(senior: @senior) : []
  end

  # GET /dashboard/senior/:senior_id/scheduling_integrations/new
  def new
    @integration = SchedulingIntegration.new(senior: @senior)
  end

  # POST /dashboard/senior/:senior_id/scheduling_integrations
  def create
    @integration = current_user.scheduling_integrations.build(integration_params)
    @integration.senior = @senior
    @integration.status = :inactive # Start inactive until verified

    # Verify credentials before saving
    if verify_and_save
      redirect_to senior_scheduling_integrations_path(@senior), 
                  notice: "Integration connected successfully!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /dashboard/scheduling_integrations/:id
  def show
    @tasks = @integration.tasks.order(scheduled_at: :desc).limit(20)
  end

  # GET /dashboard/scheduling_integrations/:id/edit
  def edit
  end

  # PATCH /dashboard/scheduling_integrations/:id
  def update
    if @integration.update(integration_params)
      redirect_to scheduling_integration_path(@integration), 
                  notice: "Integration updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /dashboard/scheduling_integrations/:id
  def destroy
    @integration.destroy
    redirect_to senior_scheduling_integrations_path(@integration.senior), 
                notice: "Integration disconnected"
  end

  # POST /dashboard/scheduling_integrations/:id/sync
  def sync
    sync_service = Scheduling::SyncService.new(@integration)
    results = sync_service.sync_appointments

    if results[:success]
      message = "Synced #{results[:created]} new and #{results[:updated]} updated appointments"
      redirect_to scheduling_integration_path(@integration), notice: message
    else
      redirect_to scheduling_integration_path(@integration), 
                  alert: "Sync failed: #{results[:error]}"
    end
  end

  # POST /dashboard/scheduling_integrations/verify
  def verify
    provider = params[:provider]
    credentials = {
      provider_user_id: params[:provider_user_id],
      api_key: params[:api_key],
      access_token: params[:access_token]
    }

    valid = Scheduling::ProviderFactory.verify_credentials(provider, credentials)

    respond_to do |format|
      format.json { render json: { valid: valid } }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { valid: false, error: e.message }, status: :unprocessable_entity }
    end
  end

  private

  def set_senior
    @senior = User.find_by(id: params[:senior_id])
  end

  def authorize_senior_access!
    return if @senior.nil?
    
    unless current_user == @senior || current_user.caregivers.include?(@senior) || @senior.caregivers.include?(current_user)
      redirect_to dashboard_path, alert: "Access denied"
    end
  end

  def set_integration
    @integration = current_user.scheduling_integrations.find(params[:id])
  end

  def integration_params
    params.require(:scheduling_integration).permit(
      :provider,
      :provider_user_id,
      :api_key,
      :api_secret,
      :access_token,
      :sync_enabled
    )
  end

  def verify_and_save
    # Verify credentials
    valid = Scheduling::ProviderFactory.verify_credentials(
      @integration.provider,
      {
        provider_user_id: @integration.provider_user_id,
        api_key: @integration.api_key,
        access_token: @integration.access_token
      }
    )

    unless valid
      @integration.errors.add(:base, "Invalid credentials. Please check your API key and user ID.")
      return false
    end

    # Mark as active and save
    @integration.status = :active
    @integration.save
  end
end
