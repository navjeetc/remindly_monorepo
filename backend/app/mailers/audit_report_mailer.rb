class AuditReportMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def daily_report(date: Date.yesterday, recipient_email:)
    @date = date
    @start_time = @date.beginning_of_day
    @end_time = @date.end_of_day
    
    # Get all login/logout events for the day
    @events = Ahoy::Event
      .includes(:user, :visit)
      .where(name: ["Login Success", "Login Failed", "Logout"])
      .where(time: @start_time..@end_time)
      .order(time: :desc)
    
    # Calculate statistics
    @total_events = @events.count
    @successful_logins = @events.where(name: "Login Success").count
    @failed_logins = @events.where(name: "Login Failed").count
    @logouts = @events.where(name: "Logout").count
    
    # Group by user
    @events_by_user = @events.group_by(&:user)
    
    # Get unique users who had activity
    @active_users = @events.map(&:user).compact.uniq
    
    mail(
      to: recipient_email,
      subject: "Daily Audit Report - #{@date.strftime('%B %d, %Y')}"
    )
  end
end
