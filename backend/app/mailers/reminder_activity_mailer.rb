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
  # Three different things can produce that, and they ask the caregiver for
  # different actions. Usually the senior was asked and did not answer. But if
  # their channel is the telephone, nobody may have been asked at all -- either
  # the reminder fell outside the hours a call may be placed, or every attempt
  # failed before it reached the provider. Saying "hasn't marked it as done" in
  # those cases reports a non-event as a lapse, and sends a caregiver looking
  # for a failure that is ours rather than theirs.
  #
  # Params: caregiver, senior, reminder, occurrence
  def missed
    setup

    # The signal first.
    #
    # This was "Mom hasn't marked Metformin as done": correct, and it reads badly
    # where a subject is actually met. The negation sat four words back in a
    # sentence nobody finishes, so the reassuring word landed last on the worst
    # available news. The other two subjects already led with what happened,
    # which is why they read correctly and this one did not.
    #
    # What is guaranteed is the opening, not the ending: the title comes last and
    # is whatever the caregiver typed, so "Check the laundry is done" still ends
    # on that word. Appending a marker to every subject to defend against an
    # unusual title would make every ordinary one read worse, and the sentence no
    # longer asserts doneness anywhere — it opens by denying it.
    subject = case @phone_failure
    when :outside_calling_hours, :not_attempted_in_time
      "Remindly couldn't call #{@senior.display_name} about #{@reminder.title}"
    when :could_not_place
      "Remindly tried to call #{@senior.display_name} about #{@reminder.title} and couldn't get through"
    else
      "No confirmation from #{@senior.display_name}: #{@reminder.title}"
    end

    # Collapsed to one line before it becomes a header. Both interpolated values
    # are typed by a person — a reminder title and a display name — and nothing
    # validates either against newlines, so one can be saved and reach this.
    #
    # Not an injection: Mail encodes a newline as =0A inside a single Subject
    # header rather than starting a new one, which was checked rather than
    # assumed. What it does produce is a subject reading
    # "No confirmation from Mom: Pills=0ABcc: ..." in the caregiver's inbox,
    # which is unreadable at exactly the moment they need to read it.
    mail(to: @caregiver.email, subject: subject.squish)
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
    @phone_failure = @occurrence.phone_failure_reason
    @attempts = @occurrence.telnyx_calls.count
    # .max, not .last: Range#last returns the end object even for an exclusive
    # range, so (8...21).last is 21 and this read "8am and 10pm" — an hour later
    # than within_calling_hours? actually allows, in an email to a caregiver.
    @calling_hours = "#{User::CALLING_HOURS.first}am and #{User::CALLING_HOURS.max + 1 - 12}pm"
  end
end
