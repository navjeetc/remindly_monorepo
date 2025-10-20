class TasksController < WebController
  before_action :authenticate!
  before_action :set_senior
  before_action :authorize_senior_access!
  before_action :set_task, only: [:show, :edit, :update, :destroy, :complete, :assign]
  layout 'dashboard'

  # GET /dashboard/senior/:senior_id/tasks
  def index
    @tasks = @senior.tasks_as_senior.includes(:assigned_to, :created_by)

    # Apply filters
    @tasks = @tasks.by_status(params[:status]) if params[:status].present?
    @tasks = @tasks.by_type(params[:task_type]) if params[:task_type].present?
    @tasks = @tasks.by_priority(params[:priority]) if params[:priority].present?
    @tasks = @tasks.assigned_to_user(params[:assigned_to]) if params[:assigned_to].present?
    @tasks = @tasks.unassigned if params[:unassigned] == "true"

    # Date range filter
    if params[:view] == "upcoming"
      @tasks = @tasks.upcoming
    elsif params[:view] == "past"
      @tasks = @tasks.past
    else
      @tasks = @tasks.order(:scheduled_at)
    end

    @tasks = @tasks.page(params[:page]).per(20)
    
    # Get caregivers for filter dropdown
    @caregivers = @senior.caregivers
  end

  # GET /dashboard/senior/:senior_id/tasks/:id
  def show
    @comments = @task.task_comments.recent.includes(:user)
  end

  # GET /dashboard/senior/:senior_id/tasks/new
  def new
    @task = @senior.tasks_as_senior.build(
      created_by: current_user,
      scheduled_at: 1.day.from_now.change(hour: 9, min: 0)
    )
    @caregivers = @senior.caregivers
  end

  # POST /dashboard/senior/:senior_id/tasks
  def create
    @task = @senior.tasks_as_senior.build(task_params)
    @task.created_by = current_user

    if @task.save
      redirect_to senior_task_path(@senior, @task), notice: "Task created successfully"
    else
      @caregivers = @senior.caregivers
      render :new, status: :unprocessable_entity
    end
  end

  # GET /dashboard/senior/:senior_id/tasks/:id/edit
  def edit
    @caregivers = @senior.caregivers
  end

  # PATCH /dashboard/senior/:senior_id/tasks/:id
  def update
    if @task.update(task_params)
      redirect_to senior_task_path(@senior, @task), notice: "Task updated successfully"
    else
      @caregivers = @senior.caregivers
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /dashboard/senior/:senior_id/tasks/:id
  def destroy
    @task.destroy
    redirect_to senior_tasks_path(@senior), notice: "Task deleted successfully"
  end

  # POST /dashboard/senior/:senior_id/tasks/:id/complete
  def complete
    if @task.update(status: :completed, completed_at: Time.current)
      redirect_to senior_task_path(@senior, @task), notice: "Task marked as complete"
    else
      redirect_to senior_task_path(@senior, @task), alert: "Could not complete task"
    end
  end

  # POST /dashboard/senior/:senior_id/tasks/:id/assign
  def assign
    caregiver = User.find(params[:caregiver_id])
    
    unless @senior.caregivers.include?(caregiver)
      redirect_to senior_task_path(@senior, @task), alert: "Invalid caregiver"
      return
    end

    if @task.update(assigned_to: caregiver, status: :assigned)
      redirect_to senior_task_path(@senior, @task), notice: "Task assigned to #{caregiver.email}"
    else
      redirect_to senior_task_path(@senior, @task), alert: "Could not assign task"
    end
  end

  private

  def set_senior
    @senior = User.find(params[:senior_id])
  end

  def authorize_senior_access!
    # User must be the senior or a caregiver for the senior
    unless current_user == @senior || current_user.seniors.include?(@senior)
      redirect_to dashboard_path, alert: "You don't have access to this senior's tasks"
    end
  end

  def set_task
    @task = @senior.tasks_as_senior.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :title,
      :description,
      :task_type,
      :status,
      :priority,
      :scheduled_at,
      :duration_minutes,
      :location,
      :notes,
      :assigned_to_id
    )
  end
end
