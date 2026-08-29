require "rails_helper"

# A caregiver reviewing Remindly described Parkinson's medication: the window is
# narrow enough that the gap between "did not answer" and "somebody was told" is
# the thing that matters.
#
# That gap was fifty minutes. The calls give up after three attempts five
# minutes apart; MarkMissedOccurrencesJob waits GRACE = 60 minutes before
# telling anybody. Nothing filled the middle.
RSpec.describe "Alerting on a critical reminder nobody answered" do
  let(:senior) { create(:user, :senior, name: "Nora", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam", email: "sam@example.com") }
  let(:hydration_only) do
    create(:user, :caregiver, name: "Pat", email: "pat@example.com",
                              notify_reminder_categories: [ "hydration" ])
  end

  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def occurrence_for(critical:, category: :medication)
    reminder = Reminder.create!(user: senior, title: "Levodopa", rrule: "FREQ=DAILY",
                                tz: senior.tz, category: category, critical: critical)
    Occurrence.create!(reminder: reminder, scheduled_at: 5.minutes.ago, status: :pending)
  end

  describe "a critical reminder" do
    it "notifies the caregiver straight away" do
      occurrence = occurrence_for(critical: true)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.to change { Notification.where(notification_type: "reminder_unanswered").count }.by(1)
    end

    # The category preference exists so nobody is woken by hydration reminders.
    # A dose somebody marked time-critical is the case it was never meant to
    # filter out, so every linked caregiver hears.
    it "reaches a caregiver who did not opt into this category" do
      CaregiverLink.create!(senior: senior, caregiver: hydration_only, permission: :manage)
      occurrence = occurrence_for(critical: true)

      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)

      expect(Notification.where(user: hydration_only, notification_type: "reminder_unanswered")).to exist
    end

    # Says "hasn't answered", not "missed": two more calls are coming, and a
    # dashboard saying missed while the phone is about to ring again would be
    # wrong for the ten minutes it matters most.
    it "does not claim the dose was missed" do
      occurrence = occurrence_for(critical: true)

      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)

      expect(Notification.last.title).to include("hasn't answered")
      expect(Notification.last.title).not_to include("missed")
    end

    # The second and third calls fire the same path. The unique index is what
    # stops a caregiver being mailed three times about one dose.
    it "tells each caregiver once, however many attempts go unanswered" do
      occurrence = occurrence_for(critical: true)

      3.times do |i|
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2 - i)
      end

      expect(Notification.where(user: caregiver, notification_type: "reminder_unanswered").count).to eq(1)
    end

    # Distinct from reminder_missed on purpose: if the dose really is missed an
    # hour later, that alert still needs to arrive. Sharing a type would let the
    # unique index swallow it.
    it "leaves the later missed alert free to send" do
      occurrence = occurrence_for(critical: true)
      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 0)

      expect {
        ReminderNotificationService.notify_missed(occurrence)
      }.to change { Notification.where(notification_type: "reminder_missed").count }.by(1)
    end
  end

  # The service enqueues with deliver_later, so nothing above renders the
  # templates. Checked here because the first manual render read as empty — the
  # body of a multipart mail is the container, not the parts, and a spec written
  # the same way would have passed against templates that did not render at all.
  # The bug this file did not catch on the first pass. The alert lived only in
  # handle_gather_ended, which runs after somebody answered and a gather
  # started, so it covered "answered and pressed nothing" and missed "the phone
  # rang out" — the more common case, and the one the flag exists for.
  describe "a call nobody picked up" do
    it "alerts from the hangup path, not only after an answered call" do
      occurrence = occurrence_for(critical: true)
      call = TelnyxCall.create!(occurrence: occurrence, user: senior, purpose: "reminder",
                                to_number: "+15551234567", status: "initiated",
                                outcome: "pending", attempt_number: 1,
                                call_day: Date.current, call_tz: senior.tz)

      controller = TelnyxWebhooksController.new

      expect {
        controller.send(:handle_hangup, call)
      }.to change { Notification.where(notification_type: "reminder_unanswered").count }.by(1)

      expect(call.reload.outcome).to eq("no_response")
    end

    it "does not alert when the call was answered and acknowledged" do
      occurrence = occurrence_for(critical: true)
      call = TelnyxCall.create!(occurrence: occurrence, user: senior, purpose: "reminder",
                                to_number: "+15551234567", status: "gathering",
                                outcome: "taken", attempt_number: 1,
                                call_day: Date.current, call_tz: senior.tz)

      expect {
        TelnyxWebhooksController.new.send(:handle_hangup, call)
      }.not_to change { Notification.count }
    end
  end

  # The guarantee the notification row exists for: it is written first precisely
  # so the alert does not depend on mail working. An earlier version of the
  # rescue deleted it to allow a re-enqueue, which meant a queue still down on
  # the last attempt left the caregiver with nothing at all.
  # The dashboard message says how many calls are still coming, and it is not
  # always more than none: this path fires on every unanswered attempt so a lost
  # webhook does not mean silence, so the notification can be written by the
  # last attempt rather than the first.
  describe "what the dashboard alert says about calls still to come" do
    it "counts them when there are some" do
      occurrence = occurrence_for(critical: true)
      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)

      expect(Notification.last.message).to include("2 more calls are on the way")
    end

    it "says one, singular, when there is one" do
      occurrence = occurrence_for(critical: true)
      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 1)

      expect(Notification.last.message).to include("One more call is on the way")
    end

    it "does not promise a call that is not coming" do
      occurrence = occurrence_for(critical: true)
      ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 0)

      expect(Notification.last.message).to include("That was the last call")
      expect(Notification.last.message).not_to include("on the way")
    end
  end

  describe "when the mail queue is broken" do
    it "keeps the in-app alert" do
      allow(ReminderActivityMailer).to receive(:with).and_raise(StandardError, "queue down")
      occurrence = occurrence_for(critical: true)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.to change { Notification.where(user: caregiver, notification_type: "reminder_unanswered").count }.by(1)
    end

    it "does not take the webhook down with it" do
      allow(ReminderActivityMailer).to receive(:with).and_raise(StandardError, "queue down")
      occurrence = occurrence_for(critical: true)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.not_to raise_error
    end
  end

  # Mirrors the acknowledged and missed paths: a hard-bounced address gets the
  # in-app alert and no mail job.
  describe "a caregiver whose email has bounced" do
    it "still gets the in-app notification" do
      caregiver.update!(email_undeliverable_at: Time.current)
      occurrence = occurrence_for(critical: true)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.to change { Notification.where(user: caregiver).count }.by(1)
    end

    it "is not sent mail" do
      caregiver.update!(email_undeliverable_at: Time.current)
      occurrence = occurrence_for(critical: true)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.not_to have_enqueued_mail(ReminderActivityMailer, :unanswered)
    end
  end

  describe "the email itself" do
    let(:occurrence) { occurrence_for(critical: true) }

    def mail
      ReminderActivityMailer
        .with(caregiver: caregiver, senior: senior, reminder: occurrence.reminder,
              occurrence: occurrence, attempts_remaining: 2)
        .unanswered
    end

    it "names the reminder in the subject, for somebody reading it at 3am" do
      expect(mail.subject).to eq("No answer yet from Nora: Levodopa")
    end

    it "says why they are hearing early, in both parts" do
      mail.parts.each do |part|
        expect(part.body.to_s).to include("time-critical"), "missing from #{part.content_type}"
      end
    end

    it "says how many calls are still coming" do
      mail.parts.each do |part|
        expect(part.body.to_s).to include("2 more"), "missing from #{part.content_type}"
      end
    end

    it "does not say the dose was missed" do
      mail.parts.each do |part|
        expect(part.body.to_s.downcase).not_to include("missed"), "present in #{part.content_type}"
      end
    end
  end

  describe "an ordinary reminder" do
    it "is left entirely alone" do
      occurrence = occurrence_for(critical: false)

      expect {
        ReminderNotificationService.notify_unanswered(occurrence, attempts_remaining: 2)
      }.not_to change { Notification.count }
    end
  end
end
