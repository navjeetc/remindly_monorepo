class ReminderActivityMailer < ApplicationMailer
  # Branded sender on the DKIM-verified remindly.care domain. (Earlier this was
  # notifications@remindly.app, which was never a confirmed Postmark sender and so
  # was rejected on every send.)
  default from: "Remindly <hello@remindly.care>"

  # A senior completed a reminder (of a category the caregiver opted into).
  # Params: caregiver, senior, reminder, occurrence
  def completed
    setup
    mail(to: @caregiver.email, subject: "#{@senior.display_name} completed #{@reminder.title}")
  end

  # A senior missed a reminder (the sweep marked it missed).
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
