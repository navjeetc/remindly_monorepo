class ReminderActivityMailer < ApplicationMailer
  default from: "notifications@remindly.app"

  # A senior completed a medication reminder.
  # Params: caregiver, senior, reminder, occurrence
  def completed
    setup
    mail(to: @caregiver.email, subject: "#{@senior.display_name} took #{@reminder.title}")
  end

  # A senior missed a medication reminder (the sweep marked it missed).
  # Params: caregiver, senior, reminder, occurrence
  def missed
    setup
    mail(to: @caregiver.email, subject: "#{@senior.display_name} missed #{@reminder.title}")
  end

  private

  def setup
    @caregiver = params[:caregiver]
    @senior = params[:senior]
    @reminder = params[:reminder]
    @occurrence = params[:occurrence]
    @scheduled_at = @occurrence.scheduled_at
    @dashboard_url = senior_dashboard_url(@senior)
  end
end
