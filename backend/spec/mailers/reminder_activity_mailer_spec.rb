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
      expect(mail.subject).to eq("Mom hasn't marked Metformin as done")
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
