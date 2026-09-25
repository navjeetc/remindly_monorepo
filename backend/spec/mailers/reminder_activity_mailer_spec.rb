require "rails_helper"

RSpec.describe ReminderActivityMailer, type: :mailer do
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:caregiver) { create(:user, :caregiver, email: "kid@example.com", name: "Jane") }
  let(:reminder) { Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.zone.local(2026, 7, 21, 9, 0), status: :acknowledged) }

  def mail_for(action)
    described_class
      .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence)
      .public_send(action)
  end

  # body.encoded is quoted-printable, which inserts soft "=\n" breaks wherever
  # the 76th column falls — so asserting on a phrase against it passes or fails
  # on line-wrap luck rather than on the copy. Decode both parts and read those.
  def readable(mail)
    [ mail.html_part, mail.text_part ].compact.map(&:decoded).join("\n")
  end

  # A senior whose only channel is the telephone, with a dose due at an hour a
  # call may not legally be placed. Nobody was asked, so the ordinary "hasn't
  # marked it as done" wording would report a non-event as a lapse.
  describe "#missed when no call was ever placed" do
    let(:senior) do
      create(:user, :senior, name: "Mom", tz: "America/New_York",
                             phone: "+15551234567", call_reminders_enabled: true)
    end
    let(:occurrence) do
      Occurrence.create!(reminder: reminder, status: :missed,
                         scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 6, 0))
    end
    let(:mail) { mail_for(:missed) }

    # Recorded by VoiceReminderJob when it refuses to dial, rather than inferred
    # later from scheduled_at — the schedule and the moment of refusal can
    # disagree, and then the wrong person gets blamed.
    before { occurrence.suppress_call!(:outside_calling_hours) }

    it "says Remindly could not call, rather than blaming the senior" do
      expect(mail.subject).to eq("Remindly couldn't call Mom about Metformin")
    end

    it "explains that nobody was contacted, and why" do
      body = readable(mail)

      expect(body).to include("Remindly did not call Mom about Metformin")
      expect(body).to include("outside the hours")
    end

    it "never claims a button went unpressed, because no device was involved" do
      expect(readable(mail)).not_to include("pressed Done on their device")
    end

    # The window is the care receiver's own now (#174), so the email has to
    # quote theirs; the old constant would name hours nobody set for them.
    it "names the care receiver's own calling hours" do
      senior.update!(calling_hours_start: 7, calling_hours_end: 20)

      expect(readable(mail_for(:missed)).squish).to include("between 7am and 8pm")
    end

    # Once a call has gone out the story is the telephone's, not the calling
    # hours' (#92): rung and unanswered reads as no answer, not as a lapse.
    it "says nobody answered once a call has rung out" do
      TelnyxCall.create!(call_control_id: "call-xyz", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response")

      expect(mail_for(:missed).subject).to eq("No answer from Mom: Metformin")
    end

    it "says there was no confirmation once somebody heard it and did not confirm" do
      TelnyxCall.create!(call_control_id: "call-xyz", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response", answered_at: Time.current)

      expect(mail_for(:missed).subject).to eq("No confirmation from Mom: Metformin")
    end

    # Subjects are glanced at, not read. The old construction put the reassuring
    # word last and the negation four words back, so a preview read "Metformin as
    # done" for a dose nobody confirmed.
    it "does not put the reassuring word last by its own construction" do
      TelnyxCall.create!(call_control_id: "call-scan", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response")

      expect(mail_for(:missed).subject).not_to match(/as done\z/)
    end

    # Nothing validates a title against newlines, so one can be saved and reach
    # the mailer. Mail encodes it as =0A inside a single Subject header rather
    # than starting a new one — so not an injection, but an unreadable subject at
    # the moment a caregiver most needs to read it.
    it "keeps the subject to one line, whatever was typed into the title" do
      TelnyxCall.create!(call_control_id: "call-newline", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response", answered_at: Time.current)
      reminder.update!(title: "Pills\nBcc: someone@example.com")

      subject = mail_for(:missed).subject

      expect(subject).not_to include("\n")
      expect(subject).to eq("No confirmation from Mom: Pills Bcc: someone@example.com")
    end

    # The title comes last and is whatever the caregiver typed, so a subject can
    # still end on "done" through no fault of the wording. What holds is the
    # opening: the sentence denies confirmation before the title is reached, so a
    # glance cannot take it for good news. Appending a marker to every subject to
    # defend against an unusual title would make every ordinary one read worse.
    it "opens by denying confirmation, even when the title itself ends in done" do
      TelnyxCall.create!(call_control_id: "call-laundry", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response", answered_at: Time.current)
      reminder.update!(title: "Check the laundry is done")

      subject = mail_for(:missed).subject

      expect(subject).to start_with("No confirmation from Mom:")
      expect(subject).to eq("No confirmation from Mom: Check the laundry is done")
    end

    # Recorded evidence outranks a setting that has since changed. Turning voice
    # reminders off does not retroactively make her someone who ignored a
    # reminder nobody delivered.
    it "still says Remindly could not call after voice reminders are switched off" do
      senior.update!(call_reminders_enabled: false)

      expect(mail_for(:missed).subject).to eq("Remindly couldn't call Mom about Metformin")
    end

    it "still says so after the phone number is cleared" do
      senior.update!(phone: nil)

      expect(mail_for(:missed).subject).to eq("Remindly couldn't call Mom about Metformin")
    end

    it "says nothing about calls for a senior who never had any recorded" do
      plain = create(:user, :senior, name: "Dad")
      plain_reminder = Reminder.create!(user: plain, title: "Walk", category: :routine,
                                        rrule: "FREQ=DAILY", tz: plain.tz)
      plain_occurrence = Occurrence.create!(reminder: plain_reminder, status: :missed,
                                            scheduled_at: Time.zone.local(2026, 7, 21, 9, 0))

      mail = described_class
        .with(caregiver: caregiver, senior: plain, reminder: plain_reminder, occurrence: plain_occurrence)
        .missed

      expect(mail.subject).to eq("No confirmation from Dad: Walk")
    end

    it "keeps the ordinary wording for a dose nothing refused to call" do
      inside = Occurrence.create!(reminder: reminder, status: :missed,
                                  scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 9, 0))
      mail = described_class
        .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: inside)
        .missed

      expect(mail.subject).to eq("No confirmation from Mom: Metformin")
    end
  end

  it "says a call was withheld even when the schedule looks like it was inside the window" do
    senior = create(:user, :senior, name: "Mom", tz: "America/New_York",
                                    phone: "+15551234567", call_reminders_enabled: true)
    reminder = Reminder.create!(user: senior, title: "Metformin", category: :medication,
                                rrule: "FREQ=DAILY", tz: senior.tz)
    # Due at 20:59, inside the window; the job did not run until 21:01, outside it.
    occurrence = Occurrence.create!(
      reminder: reminder, status: :missed,
      scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 20, 59)
    )
    occurrence.suppress_call!(:outside_calling_hours,
                              at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 21, 1))

    mail = described_class
      .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence)
      .missed

    expect(mail.subject).to eq("Remindly couldn't call Mom about Metformin")
  end

  # The sweep closed the occurrence before the queued call was ever placed. The
  # subject used to fall through to the ordinary wording while the body said
  # Remindly never called — the two contradicting each other in one message.
  describe "#missed when the call was never attempted in time" do
    let(:senior) do
      create(:user, :senior, name: "Mom", tz: "America/New_York",
                             phone: "+15551234567", call_reminders_enabled: true)
    end
    let(:occurrence) do
      Occurrence.create!(reminder: reminder, status: :missed,
                         scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 9, 0))
    end

    before { occurrence.suppress_call!(:not_attempted_in_time) }

    it "says Remindly could not call, matching the body" do
      expect(mail_for(:missed).subject).to eq("Remindly couldn't call Mom about Metformin")
    end

    it "explains that the reminder was closed before the call could be placed" do
      body = readable(mail_for(:missed))

      expect(body).to include("closed as missed")
      expect(body).to include("fault at our end")
      expect(body).not_to include("pressed Done on their device")
    end

    it "does not use the ordinary wording when the body says Remindly never called" do
      mail = mail_for(:missed)

      expect(mail.subject).not_to include("No confirmation")
      expect(readable(mail)).to include("did not call")
    end
  end

  # Attempts were claimed and every one failed before reaching the provider —
  # the state production is in right now, since it has no telnyx credentials at
  # all. Nobody was called, so blaming the senior would be doubly wrong.
  describe "#missed when the call could not be placed" do
    let(:senior) do
      create(:user, :senior, name: "Mom", tz: "America/New_York",
                             phone: "+15551234567", call_reminders_enabled: true)
    end
    let(:occurrence) do
      Occurrence.create!(reminder: reminder, status: :missed,
                         scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 9, 0))
    end

    before do
      2.times do |i|
        TelnyxCall.create!(occurrence: occurrence, user: senior, attempt_number: i + 1,
                           status: "failed", outcome: "error", completed_at: Time.current)
      end
    end

    it "says Remindly could not get through, not that the senior ignored it" do
      expect(mail_for(:missed).subject)
        .to eq("Remindly tried to call Mom about Metformin and couldn't get through")
    end

    it "owns the fault and counts the attempts" do
      body = readable(mail_for(:missed))

      expect(body).to include("could not get through")
      expect(body).to include("2 attempts")
      expect(body).to include("fault at our end")
    end

    it "never claims a button went unpressed" do
      expect(readable(mail_for(:missed))).not_to include("pressed Done on their device")
    end

    # The provider's receipt. Without a call_control_id nothing was dialled,
    # whatever the attempt row says — and with one, a call really did ring, so
    # the email is about a telephone nobody answered, not a call we failed to make.
    it "says nobody answered once one attempt actually reached the provider" do
      occurrence.telnyx_calls.first.update!(call_control_id: "v3:real-call", status: "hangup", outcome: "no_response")

      expect(mail_for(:missed).subject).to eq("No answer from Mom: Metformin")
    end
  end

  describe "#completed" do
    let(:mail) { mail_for(:completed) }

    it "addresses the caregiver" do
      expect(mail.to).to eq([ caregiver.email ])
    end

    # Branded sender on the DKIM-verified remindly.care domain, not the old
    # notifications@remindly.app, which Postmark rejected as an unconfirmed signature.
    it "sends from the verified remindly.care sender" do
      expect(mail.from).to eq([ "hello@remindly.care" ])
      expect(mail[:from].value).to eq("Remindly <hello@remindly.care>")
    end

    it "names the senior and the reminder in the subject" do
      expect(mail.subject).to eq("Mom marked Metformin as done")
    end

    it "mentions the senior and reminder in the body" do
      expect(mail.body.encoded).to include("Mom").and include("Metformin")
    end

    # The product observes a button press and nothing more. On a medication
    # reminder, "Mom completed Metformin" reads as a claim about a dose, and a
    # caregiver deciding whether to drive over is entitled to know which of the
    # two they have been told. Guarded in both directions so a future edit
    # cannot quietly reintroduce the stronger claim.
    it "claims only that the reminder was marked done, never that a dose was taken" do
      expect(readable(mail)).to include("marked Metformin as done")
      expect(readable(mail)).to match(/cannot confirm/i)
      expect(mail.subject).not_to match(/\btook\b|\btaken\b/i)
      expect(readable(mail)).not_to match(/\btook\b|\btaken\b/i)
    end

    # Copy must be category-neutral now that hydration/routine can notify too.
    it "does not describe the reminder as medication" do
      expect(mail.body.encoded).not_to match(/medication/i)
    end

    # scheduled_at is 9:00 UTC; the reminder's zone is Eastern, so the caregiver
    # should read the local morning time, not the UTC afternoon.
    it "shows the due time in the reminder's zone, not UTC" do
      expect(readable(mail)).to include("5:00 AM")
      expect(readable(mail)).not_to include("9:00 AM")
    end

    # Gmail overrides <a> link colors set only in a <style> block, so the dashboard
    # button needs inline white text to stay legible on its colored background.
    it "gives the dashboard button inline white text" do
      button = Nokogiri::HTML((mail.html_part || mail.body).decoded).at_css("a.button")
      expect(button["style"]).to match(/color:\s*#ffffff/i)
    end
  end

  describe "#missed" do
    let(:mail) { mail_for(:missed) }

    it "names the senior and the reminder in the subject" do
      expect(mail.subject).to eq("No confirmation from Mom: Metformin")
    end

    it "says the reminder was not marked done" do
      expect(readable(mail)).to include("has not marked Metformin as done")
    end

    # The alarming direction of the same problem. An unmarked reminder is not
    # evidence of a skipped dose — forgetting to press Done is at least as
    # likely — and this email is read by someone deciding whether to panic.
    it "says an unmarked reminder is not proof the thing was not done" do
      expect(readable(mail)).to match(/does not necessarily mean/i)
    end

    it "does not describe the reminder as medication" do
      expect(mail.body.encoded).not_to match(/medication/i)
    end

    it "gives the dashboard button inline white text" do
      button = Nokogiri::HTML((mail.html_part || mail.body).decoded).at_css("a.button")
      expect(button["style"]).to match(/color:\s*#ffffff/i)
    end
  end

  # The list is what this email branches on, and it has already gone stale once:
  # two reasons were added without being written down, and the second of them
  # was written with no branch in the subject case -- so the line that reached
  # the inbox was "No confirmation from Nora", which says she was asked and did
  # not answer. These walk the list instead of trusting it, so the next reason
  # cannot be added without this email having something of its own to say.
  describe "every reason in Occurrence::PHONE_FAILURE_REASONS" do
    let(:senior) { create(:user, :senior, :takes_calls, name: "Mom") }

    # A reminder per reason, all due at the same moment.
    #
    # Occurrences are unique per (reminder, scheduled_at), so sharing one
    # reminder would put each reason on a different clock time -- and the bodies
    # would then differ by the time they print, which is precisely what the
    # distinctness check below must not be satisfied by.
    def missed_mail_for(reason)
      reminder = Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz)
      occurrence = Occurrence.create!(reminder: reminder, scheduled_at: Time.zone.local(2026, 7, 21, 9, 0), status: :missed)
      occurrence.suppress_call!(reason)

      described_class
        .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence)
        .missed
    end

    Occurrence::PHONE_FAILURE_REASONS.each do |reason|
      it "does not report #{reason} as her failing to confirm" do
        mail = missed_mail_for(reason)

        expect(mail.subject).not_to include("No confirmation from")
        expect(readable(mail)).not_to include("has not marked")
      end
    end

    # Every phone failure carries the caveat, in both mails.
    #
    # It has been lost twice by being written per branch rather than once: two
    # reasons never carried it in the text mail at all, and a third shipped
    # without it. Walking the list is what makes "once, outside the branches"
    # hold rather than being a thing somebody remembers.
    %i[html_part text_part].each do |part|
      it "keeps the not-reached caveat in the #{part.to_s.sub('_part', '')} mail for every reason" do
        Occurrence::PHONE_FAILURE_REASONS.each do |reason|
          body = missed_mail_for(reason).public_send(part).decoded.gsub(/\s+/, " ")

          expect(body).to include("says nothing about whether they did it"),
                          "#{reason} lost the caveat in the #{part}"
        end
      end
    end

    # The check the one above is not.
    #
    # A reason with no branch of its own does not fall through to "has not
    # marked" -- it falls into the generic phone-failure branch, which is the
    # calling-hours sentence, and tells a caregiver the call fell outside the
    # hours calls may be placed when it did not. That reads as an explanation
    # and is a different reason's explanation. Every reason owning its own body
    # is the only thing that catches it.
    #
    # Per part, not across both. The two templates are structured differently --
    # the HTML mail carries the shared caveat outside its branches and the text
    # mail repeats it inside each one -- and #137 landed with a branch in one and
    # not the other for exactly that reason. Read as one string, a reason
    # branched in the HTML mail alone still looks distinct, while the text mail
    # quietly tells a text-only reader a different reason's story. Checked
    # against that: with a fifth reason branched in HTML only, the joined version
    # of this passed.
    %i[html_part text_part].each do |part|
      it "gives each reason a sentence of its own in the #{part.to_s.sub('_part', '')} mail" do
        bodies = Occurrence::PHONE_FAILURE_REASONS.map do |reason|
          missed_mail_for(reason).public_send(part).decoded
        end

        expect(bodies.uniq.size).to eq(Occurrence::PHONE_FAILURE_REASONS.size)
      end
    end
  end

  # #92: calls went out, and the email has to say what the telephone saw rather
  # than describe a screen button the person may not have.
  describe "#missed after reminder calls rang" do
    let(:senior) do
      create(:user, :senior, name: "Mom", tz: "America/New_York",
                             phone: "+15551234567", call_reminders_enabled: true)
    end
    let(:occurrence) do
      Occurrence.create!(reminder: reminder, status: :missed,
                         scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 8, 0))
    end

    def ring(id, answered_at: nil)
      TelnyxCall.create!(call_control_id: id, occurrence: occurrence, user: senior,
                         attempt_number: occurrence.telnyx_calls.count + 1,
                         status: "hangup", outcome: "no_response", answered_at: answered_at)
    end

    context "when nobody pressed 1 on any of them" do
      before { 3.times { |i| ring("call-#{i}") } }

      let(:body) { readable(mail_for(:missed)).squish }

      # "never heard", not "nobody answered": somebody can pick up and put the
      # phone down without a key, and that looks the same as a ring-out.
      it "says how many times Remindly called and that the reminder was never heard" do
        expect(body).to include("Remindly called Mom 3 times about Metformin, and the reminder was never heard")
        expect(body).not_to include("nobody answered")
      end

      it "does not describe a screen button, or suggest it was done without marking" do
        expect(body).not_to include("pressed Done on their device")
        expect(body).not_to include("may have done it without marking it")
      end

      it "suggests checking in rather than reassuring" do
        expect(body).to include("it may be worth checking in")
      end

      it "heads the email as no answer" do
        heading = Nokogiri::HTML(mail_for(:missed).html_part.decoded).at_css("h1").text
        expect(heading).to include("No answer")
      end
    end

    context "when somebody pressed 1, heard it, and did not confirm" do
      before do
        ring("call-0")
        ring("call-1", answered_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 7, 21, 8, 6))
      end

      let(:body) { readable(mail_for(:missed)).squish }

      it "says it was heard, and when, in their time" do
        # "was answered", not "Mom heard": a keypress proves a person, not which one.
        expect(body).to include("Remindly's call to Mom about Metformin was answered, but nobody confirmed it")
        # Any key starts the reminder, so the email cannot say which one.
        expect(body).to include("pressed a key to hear it at 8:06 AM")
      end

      it "does not claim the reminder went unheard" do
        expect(body).not_to include("never heard")
      end
    end
  end

  # #171: the due time was printed in the senior's zone with nothing to say so,
  # which a caregiver hours away reads on their own clock.
  describe "the due time" do
    let(:senior) { create(:user, :senior, name: "Mom", tz: "America/Halifax") }
    let(:caregiver) { create(:user, :caregiver, email: "kid@example.com", name: "Jane", tz: "America/Los_Angeles") }
    let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.utc(2026, 7, 21, 16, 42), status: :missed) }

    it "names whose time it is, and the caregiver's own, when they differ" do
      body = readable(mail_for(:missed)).squish

      expect(body).to include("Tuesday, July 21 at 1:42 PM, Mom's time (ADT) — 9:42 AM your time")
    end

    it "labels the time on the completed and unanswered emails too" do
      expect(readable(mail_for(:completed)).squish).to include("Mom's time (ADT)")

      unanswered = described_class
        .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence, attempts_remaining: 2)
        .unanswered
      expect(readable(unanswered).squish).to include("1:42 PM, Mom's time (ADT) — 9:42 AM your time")
    end

    it "leaves out the caregiver's time when both clocks read the same" do
      caregiver.update!(tz: "America/Halifax")

      body = readable(mail_for(:missed)).squish

      expect(body).to include("1:42 PM, Mom's time (ADT)")
      expect(body).not_to include("your time")
    end

    # A reminder keeps the zone it was saved in until it is next written, so a
    # senior who has moved can have reminders stamped with their old clock. The
    # email calls the time "Mom's time", so it has to read it on her clock now.
    it "reads the time on the senior's current clock, not the reminder's old stamp" do
      reminder.update_columns(tz: "America/New_York")

      body = readable(mail_for(:missed)).squish

      expect(body).to include("1:42 PM, Mom's time (ADT)")
      expect(body).not_to include("EDT")
    end

    # The no-answer alert shows times without a date; when the clocks are on
    # different days, two bare times cannot say which day either one is.
    it "names both days in the short label when the clocks are on different days" do
      senior.update!(tz: "Asia/Tokyo")
      reminder.update!(tz: "Asia/Tokyo")

      unanswered = described_class
        .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence, attempts_remaining: 2)
        .unanswered

      expect(readable(unanswered).squish).to include("Wednesday 1:42 AM, Mom's time (JST) — Tuesday 9:42 AM your time")
    end

    it "names the day as well when the caregiver's clock has crossed midnight" do
      senior.update!(tz: "Asia/Tokyo")
      reminder.update!(tz: "Asia/Tokyo")

      body = readable(mail_for(:missed)).squish

      # 16:42 UTC is 1:42 AM Wednesday in Tokyo and 9:42 AM Tuesday in Los Angeles.
      expect(body).to include("Wednesday, July 22 at 1:42 AM, Mom's time (JST) — Tuesday 9:42 AM your time")
    end
  end
end
