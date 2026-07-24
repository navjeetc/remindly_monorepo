require "rails_helper"

RSpec.describe ReminderNotificationService do
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:caregiver) { create(:user, :caregiver, email: "kid@example.com", name: "Jane") }

  def link!(cg, to: senior)
    CaregiverLink.create!(senior: to, caregiver: cg)
  end

  def occurrence_for(category: :medication, title: "Metformin")
    reminder = Reminder.create!(user: senior, title: title, category: category, rrule: "FREQ=DAILY", tz: senior.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending)
  end

  describe ".notify_acknowledged" do
    it "creates an in-app notification and enqueues an email for each opted-in caregiver" do
      link!(caregiver)
      occ = occurrence_for

      expect {
        expect { described_class.notify_acknowledged(occ) }
          .to have_enqueued_mail(ReminderActivityMailer, :completed).with(hash_including(params: hash_including(caregiver: caregiver)))
      }.to change { caregiver.notifications.count }.by(1)

      note = caregiver.notifications.last
      expect(note.notification_type).to eq(Notification::TYPES[:reminder_acknowledged])
      expect(note.title).to include("Mom").and include("Metformin")
      expect(note.metadata["occurrence_id"]).to eq(occ.id)
    end

    it "notifies every linked caregiver who is opted in" do
      link!(caregiver)
      other = create(:user, :caregiver, email: "other@example.com")
      link!(other)

      expect { described_class.notify_acknowledged(occurrence_for) }
        .to change { Notification.count }.by(2)
    end

    it "skips a caregiver who chose no categories" do
      caregiver.update!(notify_reminder_categories: [])
      link!(caregiver)

      expect { described_class.notify_acknowledged(occurrence_for) }
        .not_to change { Notification.count }
    end

    it "does not notify for a category the caregiver has not opted into" do
      # Hydration is off by default.
      link!(caregiver)
      occ = occurrence_for(category: :hydration, title: "Water")

      expect {
        expect { described_class.notify_acknowledged(occ) }.not_to change { Notification.count }
      }.not_to have_enqueued_mail(ReminderActivityMailer, :completed)
    end

    it "notifies for a non-medication category the caregiver opted into" do
      caregiver.update!(notify_reminder_categories: %w[medication hydration])
      link!(caregiver)
      occ = occurrence_for(category: :hydration, title: "Water")

      # Both channels, same as the medication path — an in-app record and an email.
      expect { described_class.notify_acknowledged(occ) }
        .to change { caregiver.notifications.count }.by(1)
        .and have_enqueued_mail(ReminderActivityMailer, :completed)
    end

    it "notifies only the caregivers opted into this reminder's category" do
      link!(caregiver) # medication only (default)
      hydration_fan = create(:user, :caregiver, email: "water@example.com", notify_reminder_categories: %w[hydration])
      link!(hydration_fan)

      # A medication reminder reaches the medication caregiver, not the hydration one.
      expect { described_class.notify_acknowledged(occurrence_for(category: :medication)) }
        .to change { caregiver.notifications.count }.by(1)
        .and change { hydration_fan.notifications.count }.by(0)
    end

    it "does nothing when the senior has no caregivers" do
      expect { described_class.notify_acknowledged(occurrence_for) }
        .not_to change { Notification.count }
    end

    # The job that calls this retries on failure, so a second run over the same
    # occurrence must not notify a caregiver who already got through.
    it "does not notify the same caregiver twice about the same occurrence" do
      link!(caregiver)
      occ = occurrence_for

      described_class.notify_acknowledged(occ)

      expect { described_class.notify_acknowledged(occ) }
        .not_to change { Notification.count }
    end
  end

  describe ".notify_missed" do
    it "creates a missed notification and enqueues the missed email" do
      link!(caregiver)
      occ = occurrence_for

      expect {
        expect { described_class.notify_missed(occ) }
          .to have_enqueued_mail(ReminderActivityMailer, :missed)
      }.to change { caregiver.notifications.count }.by(1)

      expect(caregiver.notifications.last.notification_type).to eq(Notification::TYPES[:reminder_missed])
      expect(caregiver.notifications.last.title).to include("missed")
    end
  end
end
