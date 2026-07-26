class Admin::AuditLogsController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout "dashboard"

  def index
    @event_filter = params[:event_filter]
    @user_filter = params[:user_id]
    @date_from = params[:date_from]
    @date_to = params[:date_to]

    filtered = filtered_events

    # The summary tiles count the same rows the table lists. Counting all events
    # here instead would put an all-time total next to a filtered list, and the
    # three numbers would not add up whenever a filter is applied.
    @total_events = filtered.count
    @successful_logins = filtered.where(name: "Login Success").count
    @failed_logins = filtered.where(name: "Login Failed").count

    @events = filtered.includes(:user, :visit).page(params[:page]).per(50)

    # Get unique event names for filter dropdown
    @event_names = Ahoy::Event.distinct.pluck(:name).sort

    # Get users who have events for filter dropdown
    @users_with_events = User.joins(:events).distinct.order(:email)
  end

  def show
    @event = Ahoy::Event.includes(:user, :visit).find(params[:id])
  end

  private

  def filtered_events
    events = Ahoy::Event.order(time: :desc)
    events = events.where(name: @event_filter) if @event_filter.present?
    events = events.where(user_id: @user_filter) if @user_filter.present?

    from = parse_filter_date(@date_from)
    to = parse_filter_date(@date_to)
    events = events.where("time >= ?", from.beginning_of_day) if from
    events = events.where("time <= ?", to.end_of_day) if to
    events
  end

  # A hand-edited query string should not take the page down. Date.parse raises
  # on anything it cannot read, so an unparseable bound is dropped and the
  # remaining filters still apply.
  def parse_filter_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    Rails.logger.warn "Admin::AuditLogsController: ignoring unparseable date filter #{value.inspect}"
    nil
  end

  def require_admin!
    unless current_user&.role_admin?
      redirect_to dashboard_path, alert: "Access denied. Admin privileges required."
    end
  end
end
