module Api
  class TasksController < ApplicationController
    before_action :authenticate_user!
    before_action :set_task, only: [:show, :update, :destroy, :assign, :claim]
    before_action :authorize_task_access, only: [:show, :update, :destroy]

    # GET /api/tasks
    def index
      @tasks = Task.all

      # Filter by senior
      @tasks = @tasks.for_senior(params[:senior_id]) if params[:senior_id].present?

      # Filter by assigned caregiver
      @tasks = @tasks.assigned_to_user(params[:assigned_to]) if params[:assigned_to].present?

      # Filter by status
      @tasks = @tasks.by_status(params[:status]) if params[:status].present?

      # Filter by task type
      @tasks = @tasks.by_type(params[:task_type]) if params[:task_type].present?

      # Filter by priority
      @tasks = @tasks.by_priority(params[:priority]) if params[:priority].present?

      # Filter by date range
      if params[:start_date].present? && params[:end_date].present?
        @tasks = @tasks.in_date_range(params[:start_date], params[:end_date])
      end

      # Filter unassigned
      @tasks = @tasks.unassigned if params[:unassigned] == "true"

      # Default ordering
      @tasks = @tasks.order(:scheduled_at)

      # Pagination
      page = params[:page] || 1
      per_page = params[:per_page] || 50

      @tasks = @tasks.page(page).per(per_page)

      render json: {
        tasks: @tasks.as_json(include: {
          senior: { only: [:id, :email, :name] },
          assigned_to: { only: [:id, :email, :name] },
          created_by: { only: [:id, :email, :name] }
        }),
        meta: {
          current_page: @tasks.current_page,
          total_pages: @tasks.total_pages,
          total_count: @tasks.total_count
        }
      }
    end

    # GET /api/tasks/:id
    def show
      render json: @task.as_json(include: {
        senior: { only: [:id, :email, :name] },
        assigned_to: { only: [:id, :email, :name] },
        created_by: { only: [:id, :email, :name] },
        task_comments: {
          include: {
            user: { only: [:id, :email, :name] }
          }
        }
      })
    end

    # POST /api/tasks
    def create
      @task = Task.new(task_params)
      @task.created_by = current_user

      if @task.save
        # TODO: Send notification to assigned caregiver if assigned
        render json: @task, status: :created
      else
        render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /api/tasks/:id
    def update
      if @task.update(task_params)
        # TODO: Send notification on status change
        render json: @task
      else
        render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/tasks/:id
    def destroy
      @task.destroy
      head :no_content
    end

    # POST /api/tasks/:id/assign
    def assign
      assigned_user = User.find(params[:assigned_to_id])

      # Verify the assigned user is a caregiver for this senior
      unless assigned_user.seniors.include?(@task.senior)
        return render json: { error: "User is not a caregiver for this senior" }, status: :forbidden
      end

      if @task.update(assigned_to: assigned_user, status: :assigned)
        # TODO: Send notification to assigned caregiver
        render json: @task
      else
        render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # POST /api/tasks/:id/claim
    def claim
      # Verify current user is a caregiver for this senior
      unless current_user.seniors.include?(@task.senior)
        return render json: { error: "You are not a caregiver for this senior" }, status: :forbidden
      end

      if @task.update(assigned_to: current_user, status: :assigned)
        # TODO: Send notification
        render json: @task
      else
        render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_task
      @task = Task.find(params[:id])
    end

    def authorize_task_access
      # User must be either the senior, a caregiver for the senior, or the creator
      unless current_user == @task.senior ||
             current_user.seniors.include?(@task.senior) ||
             current_user == @task.created_by
        render json: { error: "Unauthorized" }, status: :forbidden
      end
    end

    def task_params
      params.require(:task).permit(
        :senior_id,
        :assigned_to_id,
        :title,
        :description,
        :task_type,
        :status,
        :priority,
        :scheduled_at,
        :duration_minutes,
        :location,
        :notes,
        :completed_at
      )
    end
  end
end
