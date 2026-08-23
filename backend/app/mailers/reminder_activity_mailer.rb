class ReminderActivityMailer < ApplicationMailer
  # This is where the remindly.app bug was found and fixed — here and in
  # CoverageGapMailer only, which is why the other six kept the broken
  # fallback for so long. Both now inherit the sender from ApplicationMailer
  # instead of restating it.

  # Subjects say what Remindly actually observed — that Done was pressed, or
  # that it was not — rather than what a caregiver might infer from it. For a
  # medication reminder "Mom completed Metformin" is a claim about a dose; all
  # this product knows is that a button was pressed on a device. The distinction
  # is invisible on a good day and the whole ballgame on a bad one.

  # A senior marked a reminder done (of a category the caregiver opted into).
  # Params: caregiver, senior, reminder, occurrence
  def completed
    setup
    mail(to: @caregiver.email, subject: "#{@senior.display_name} marked #{@reminder.title} as done")
  end

  # Nobody marked the reminder done before the sweep closed it out.
  #
  # Two different things can produce that, and they ask the caregiver for
  # different actions. Usually the senior was asked and did not answer. But if
  # their only channel is the telephone and the reminder fell outside the hours
  # a call may be placed, nobody was asked at all -- and saying "hasn't marked
  # it as done" would report a non-event as a lapse.
  #
  # Params: caregiver, senior, reminder, occurrence
  def missed
    setup

    subject = if @phone_call_withheld
      "Remindly couldn't call #{@senior.display_name} about #{@reminder.title}"
    else
      "#{@senior.display_name} hasn't marked #{@reminder.title} as done"
    end

    mail(to: @caregiver.email, subject: subject)
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
    @phone_call_withheld = @occurrence.phone_call_withheld?
    @calling_hours = "#{User::CALLING_HOURS.first}am and #{User::CALLING_HOURS.last + 1 - 12}pm"
  end
end
