class Admin::UsersController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout 'dashboard'
  
  def index
    @role_filter = params[:role_filter]
    
    # Eager load caregiver_links with seniors to avoid N+1 queries
    @users = User.includes(caregiver_links: :senior).order(created_at: :desc)
    
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
    old_role = @user.role
    new_role = params[:role].presence
    
    # Update role without triggering name validation
    @user.update_column(:role, new_role)
    
    # Send notification to user about role change
    if old_role != new_role
      RoleChangeMailer.role_updated(
        user: @user,
        old_role: old_role,
        new_role: new_role,
        changed_by: current_user
      ).deliver_later
    end
    
    redirect_to admin_users_path, notice: "Role updated for #{@user.email}"
  end
  
  private
  
  def require_admin!
    unless current_user&.role_admin?
      redirect_to dashboard_path, alert: "Access denied. Admin privileges required."
    end
  end
end
