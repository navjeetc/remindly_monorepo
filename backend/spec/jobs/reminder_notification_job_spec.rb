require "rails_helper"

RSpec.describe ReminderNotificationJob do
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:caregiver) { create(:user, :caregiver, email: "kid@example.com", name: "Jane") }

  before { CaregiverLink.create!(senior: senior, caregiver: caregiver) }

  def occurrence(status:, category: :medication)
    reminder = Reminder.create!(user: senior, title: "Metformin", category: category, rrule: "FREQ=DAILY", tz: senior.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: status)
  end

  it "delivers a completion notification when the occurrence is acknowledged" do
    occ = occurrence(status: :acknowledged)
    expect { described_class.perform_now(occ.id, "acknowledged") }
      .to change { caregiver.notifications.count }.by(1)
    expect(caregiver.notifications.last.notification_type).to eq(Notification::TYPES[:reminder_acknowledged])
  end

  it "delivers a missed notification when the occurrence is missed" do
    occ = occurrence(status: :missed)
    expect { described_class.perform_now(occ.id, "missed") }
      .to change { caregiver.notifications.count }.by(1)
  end

  # The status can move between enqueue and run — a late take flips missed back to
  # acknowledged — and we must not announce the stale event.
  it "does nothing if the occurrence no longer matches the announced status" do
    occ = occurrence(status: :acknowledged)
    expect { described_class.perform_now(occ.id, "missed") }
      .not_to change { Notification.count }
  end

  it "does nothing if the occurrence was deleted" do
    expect { described_class.perform_now(-1, "acknowledged") }
      .not_to change { Notification.count }
  end
end
