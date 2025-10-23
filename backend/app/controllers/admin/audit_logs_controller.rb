class Admin::AuditLogsController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout 'dashboard'
  
  def index
    @event_filter = params[:event_filter]
    @user_filter = params[:user_id]
    @date_from = params[:date_from]
    @date_to = params[:date_to]
    
    # Base query with user association
    @events = Ahoy::Event.includes(:user, :visit).order(time: :desc)
    
    # Apply filters
    if @event_filter.present?
      @events = @events.where(name: @event_filter)
    end
    
    if @user_filter.present?
      @events = @events.where(user_id: @user_filter)
    end
    
    if @date_from.present?
      @events = @events.where("time >= ?", Date.parse(@date_from).beginning_of_day)
    end
    
    if @date_to.present?
      @events = @events.where("time <= ?", Date.parse(@date_to).end_of_day)
    end
    
    # Paginate results
    @events = @events.page(params[:page]).per(50)
    
    # Get unique event names for filter dropdown
    @event_names = Ahoy::Event.distinct.pluck(:name).sort
    
    # Get users who have events for filter dropdown
    @users_with_events = User.joins(:events).distinct.order(:email)
  end
  
  def show
    @event = Ahoy::Event.includes(:user, :visit).find(params[:id])
  end
  
  private
  
  def require_admin!
    unless current_user&.role_admin?
      redirect_to dashboard_path, alert: "Access denied. Admin privileges required."
    end
  end
end
