class TaskCommentsController < WebController
  before_action :authenticate!
  before_action :set_senior_and_task
  before_action :authorize_task_access!

  # POST /dashboard/senior/:senior_id/tasks/:task_id/comments
  def create
    @comment = @task.task_comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      redirect_to senior_task_path(@senior, @task), notice: "Comment added"
    else
      redirect_to senior_task_path(@senior, @task), alert: "Could not add comment"
    end
  end

  # DELETE /dashboard/senior/:senior_id/tasks/:task_id/comments/:id
  def destroy
    @comment = @task.task_comments.find(params[:id])
    
    # Only the comment author can delete
    if @comment.user == current_user
      @comment.destroy
      redirect_to senior_task_path(@senior, @task), notice: "Comment deleted"
    else
      redirect_to senior_task_path(@senior, @task), alert: "You can only delete your own comments"
    end
  end

  private

  def set_senior_and_task
    @senior = User.find(params[:senior_id])
    @task = @senior.tasks_as_senior.find(params[:task_id])
  end

  def authorize_task_access!
    unless current_user == @senior || current_user.seniors.include?(@senior)
      redirect_to dashboard_path, alert: "You don't have access to this task"
    end
  end

  def comment_params
    params.require(:task_comment).permit(:content)
  end
end
