module Api
  class TaskCommentsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_task
    before_action :authorize_task_access

    # GET /api/tasks/:task_id/comments
    def index
      @comments = @task.task_comments.recent.includes(:user)

      render json: @comments.as_json(include: {
        user: { only: [:id, :email, :name] }
      })
    end

    # POST /api/tasks/:task_id/comments
    def create
      @comment = @task.task_comments.build(comment_params)
      @comment.user = current_user

      if @comment.save
        # TODO: Send notification to other caregivers
        render json: @comment.as_json(include: {
          user: { only: [:id, :email, :name] }
        }), status: :created
      else
        render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/tasks/:task_id/comments/:id
    def destroy
      @comment = @task.task_comments.find(params[:id])

      # Only the comment author can delete
      unless @comment.user == current_user
        return render json: { error: "Unauthorized" }, status: :forbidden
      end

      @comment.destroy
      head :no_content
    end

    private

    def set_task
      @task = Task.find(params[:task_id])
    end

    def authorize_task_access
      # User must be either the senior, a caregiver for the senior, or the creator
      unless current_user == @task.senior ||
             current_user.seniors.include?(@task.senior) ||
             current_user == @task.created_by
        render json: { error: "Unauthorized" }, status: :forbidden
      end
    end

    def comment_params
      params.require(:comment).permit(:content)
    end
  end
end
