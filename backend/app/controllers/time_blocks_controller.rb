class TimeBlocksController < WebController
  before_action :authenticate!
  before_action :set_senior
  before_action :authorize_senior_access!
  before_action :set_time_block, only: [:edit, :update, :destroy]
  layout 'dashboard'

  # GET /dashboard/senior/:senior_id/time_blocks
  def index
    @time_blocks = @senior.time_blocks.active.order(:start_time)
  end

  # GET /dashboard/senior/:senior_id/time_blocks/new
  def new
    @time_block = @senior.time_blocks.build(
      start_time: Time.current.change(hour: 22, min: 0),
      end_time: Time.current.tomorrow.change(hour: 7, min: 0)
    )
  end

  # POST /dashboard/senior/:senior_id/time_blocks
  def create
    @time_block = @senior.time_blocks.build(time_block_params)

    if @time_block.save
      redirect_to senior_time_blocks_path(@senior), notice: "Time block created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /dashboard/senior/:senior_id/time_blocks/:id/edit
  def edit
  end

  # PATCH /dashboard/senior/:senior_id/time_blocks/:id
  def update
    if @time_block.update(time_block_params)
      redirect_to senior_time_blocks_path(@senior), notice: "Time block updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /dashboard/senior/:senior_id/time_blocks/:id
  def destroy
    @time_block.destroy
    redirect_to senior_time_blocks_path(@senior), notice: "Time block deleted successfully"
  end

  private

  def set_senior
    @senior = User.find(params[:senior_id])
  end

  def authorize_senior_access!
    # User must be the senior or a caregiver for the senior
    unless current_user == @senior || current_user.seniors.include?(@senior)
      redirect_to dashboard_path, alert: "You don't have access to this senior's time blocks"
    end
  end

  def set_time_block
    @time_block = @senior.time_blocks.find(params[:id])
  end

  def time_block_params
    params.require(:time_block).permit(
      :start_time,
      :end_time,
      :reason,
      :recurring,
      :recurrence_pattern,
      :active
    )
  end
end
