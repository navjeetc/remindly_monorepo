class Admin::UsersController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout 'dashboard'
  
  def index
    @users = User.order(created_at: :desc)
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
