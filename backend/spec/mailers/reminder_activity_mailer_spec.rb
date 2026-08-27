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

    it "falls back to the ordinary wording once a call has actually gone out" do
      TelnyxCall.create!(call_control_id: "call-xyz", occurrence: occurrence, user: senior,
                         status: "hangup", outcome: "no_response")

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
                         status: "hangup", outcome: "no_response")
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
                         status: "hangup", outcome: "no_response")
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
    # whatever the attempt row says — and with one, a call really did ring and
    # went unanswered, which is an ordinary miss.
    it "reverts to the ordinary wording once one attempt actually reached the provider" do
      occurrence.telnyx_calls.first.update!(call_control_id: "v3:real-call", status: "hangup", outcome: "no_response")

      expect(mail_for(:missed).subject).to eq("No confirmation from Mom: Metformin")
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
      expect(mail.body.encoded).to include("05:00 AM")
      expect(mail.body.encoded).not_to include("09:00 AM")
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
end
