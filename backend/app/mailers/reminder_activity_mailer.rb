class ReminderActivityMailer < ApplicationMailer
  # This was the one mailer with a correct sender — it had the same
  # remindly.app bug and was fixed here alone, which is why every other mailer
  # kept the broken fallback. The branded sender now lives on ApplicationMailer
  # and this inherits it, so there is one definition rather than one good one
  # and six bad ones.

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
