class ReminderActivityMailer < ApplicationMailer
  # Use the account's verified Postmark sender (as MagicMailer does). The old
  # hardcoded notifications@remindly.app is not a confirmed Sender Signature, so
  # Postmark rejected every send with ApiInputError.
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

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
    # Present the due time in the senior's zone; the raw timestamp is UTC and the
    # templates strftime it, so an Eastern 9:00 AM dose would otherwise read 1:00 PM.
    @scheduled_at = @occurrence.scheduled_at&.in_time_zone(@reminder.tz)
    @dashboard_url = senior_dashboard_url(@senior)
  end
end
