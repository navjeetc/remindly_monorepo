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

    it "skips a caregiver who turned reminder activity off" do
      caregiver.update!(notify_on_reminder_activity: false)
      link!(caregiver)

      expect { described_class.notify_acknowledged(occurrence_for) }
        .not_to change { Notification.count }
    end

    it "does nothing for a non-medication reminder" do
      link!(caregiver)
      occ = occurrence_for(category: :hydration, title: "Water")

      expect {
        expect { described_class.notify_acknowledged(occ) }.not_to change { Notification.count }
      }.not_to have_enqueued_mail(ReminderActivityMailer, :completed)
    end

    it "does nothing when the senior has no caregivers" do
      expect { described_class.notify_acknowledged(occurrence_for) }
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
