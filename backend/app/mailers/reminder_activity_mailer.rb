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
    subject = case @phone_failure || @phone_calls
    when :no_answer
      # Rung, and nobody pressed 1 to hear it. Said as what it is rather than
      # folded into "no confirmation", which reads as her having heard and not
      # confirmed -- a milder thing than a telephone nobody answered (#92).
      "No answer from #{@senior.display_name}: #{@reminder.title}"
    when :outside_calling_hours, :not_attempted_in_time
      "Remindly couldn't call #{@senior.display_name} about #{@reminder.title}"
    # "didn't", not "couldn't": the others are Remindly unable to place a call,
    # this one is Remindly declining to. Nothing stopped us -- the time had
    # simply gone by before the reminder existed, and we do not ring about a dose
    # whose moment has passed. The distinction is the same one the body makes,
    # and the subject has to carry it too: this branch was missing, so the
    # sentence that reached the inbox was "No confirmation from Nora", which
    # reads as her having been asked and not answered. No call was placed.
    #
    # No call was placed, and not "she was never asked", which is what this said
    # until the templates below stopped saying it: the screen client announces a
    # back-filled row like any other, so whether she was asked is a question this
    # email cannot answer. What it knows is that the telephone stayed quiet.
    when :added_after_its_time
      "Remindly didn't call #{@senior.display_name} about #{@reminder.title}"
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

  # A call for a critical reminder went unanswered.
  #
  # Says nobody has picked up yet, not that the dose was missed. The distinction
  # is the whole point: this arrives about a minute after a ring, where the
  # missed alert waits an hour, and a caregiver acting on it may still catch the
  # dose in time.
  #
  # How many calls remain is passed in rather than assumed. Usually two, since
  # the first unanswered attempt is normally the first webhook to arrive — but
  # this fires on every attempt so a lost delivery does not mean silence, and
  # the last one may be the only one that lands.
  #
  # Params: caregiver, senior, reminder, occurrence, attempts_remaining
  def unanswered
    setup
    @attempts_remaining = params[:attempts_remaining]

    # Names the reminder, because a caregiver receiving this at 3am needs to know
    # which one before deciding whether to get up.
    subject = "No answer yet from #{@senior.display_name}: #{@reminder.title}"

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
    @calling_hours = @senior.calling_hours_label
    @due_label = due_label
    @due_time_label = due_label(with_date: false)
    @phone_calls = phone_calls
  end

  # What the telephone can say about a reminder it did ring for (#92), when
  # phone_failure_reason has nothing to report because calls did go out:
  #
  #   :no_answer  every call rang out without anybody pressing 1 to hear the
  #               reminder -- nobody picked up, or a machine did; a mailbox
  #               cannot press a key, which is what the opening line is for
  #   :heard      somebody pressed 1 and heard it, and did not confirm
  #
  # nil when no call was placed at all, which leaves the screen wording. Only
  # calls with a provider receipt count, as in phone_failure_reason.
  def phone_calls
    return if @phone_failure

    placed = @occurrence.telnyx_calls.where.not(call_control_id: nil)
    @calls_placed = placed.count
    return if @calls_placed.zero?

    @heard_at = placed.where.not(answered_at: nil).minimum(:answered_at)&.in_time_zone(@reminder.tz)
    @heard_at ? :heard : :no_answer
  end

  # "Monday, September 21 at 8:15 AM, Mom's time (EDT)" -- and, when the
  # caregiver's clock reads differently, "— 5:15 AM your time" (#171).
  #
  # The senior's zone stays first because it is the one the reminder was set
  # in. Naming it matters because the product's premise is a caregiver hours
  # away: an unlabelled "1:42 PM" read on a coast three hours behind is a
  # missed email about their own future.
  def due_label(with_date: true)
    return if @scheduled_at.nil?

    theirs = @scheduled_at.strftime(with_date ? "%A, %B %-d at %-l:%M %p" : "%-l:%M %p")
    label = "#{theirs}, #{@senior.display_name}'s time (#{@scheduled_at.strftime('%Z')})"

    caregiver_zone = ActiveSupport::TimeZone[@caregiver.tz.to_s]
    return label if caregiver_zone.nil?

    yours = @scheduled_at.in_time_zone(caregiver_zone)
    return label if yours.utc_offset == @scheduled_at.utc_offset

    # The day as well, when it differs: 11pm theirs can be tomorrow yours.
    format = yours.to_date == @scheduled_at.to_date ? "%-l:%M %p" : "%A %-l:%M %p"
    "#{label} — #{yours.strftime(format)} your time"
  end
end
