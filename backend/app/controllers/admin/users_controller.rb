class Admin::UsersController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout 'dashboard'
  
  def index
    @role_filter = params[:role_filter]
    
    @users = User.order(created_at: :desc)
    
    # Apply role filter if present
    if @role_filter.present?
      if @role_filter == 'none'
        @users = @users.where(role: nil)
      else
        @users = @users.where(role: @role_filter)
      end
    end
  end
  
  def update_role
    @user = User.find(params[:id])
    new_role = params[:role].presence
    
    @user.update!(role: new_role)
    redirect_to admin_users_path, notice: "Role updated for #{@user.email}"
  end
  
  private
  
  def require_admin!
    unless current_user&.role_admin?
      redirect_to dashboard_path, alert: "Access denied. Admin privileges required."
    end
  end
end
