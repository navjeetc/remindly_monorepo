class NotificationsController < WebController
  before_action :authenticate!
  before_action :set_notification, only: [:mark_read]
  layout 'dashboard'

  # GET /notifications
  def index
    @notifications = current_user.notifications
                                 .recent
                                 .page(params[:page])
                                 .per(20)
    
    @unread_count = current_user.notifications.unread.count
  end

  # POST /notifications/:id/mark_read
  def mark_read
    @notification.mark_as_read!
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.json { head :no_content }
    end
  end

  # POST /notifications/mark_all_read
  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    
    redirect_to notifications_path, notice: "All notifications marked as read"
  end

  private

  def set_notification
    @notification = current_user.notifications.find(params[:id])
  end
end
