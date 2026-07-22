require "rails_helper"

RSpec.describe MarkMissedOccurrencesJob do
  let(:senior) { create(:user, :senior, name: "Mom") }

  def occurrence_at(scheduled_at, category: :medication, status: :pending)
    reminder = Reminder.create!(user: senior, title: "Metformin", category: category, rrule: "FREQ=DAILY", tz: senior.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: scheduled_at, status: status)
  end

  describe "marking" do
    it "marks a pending occurrence missed once past the grace window" do
      occ = occurrence_at(90.minutes.ago)
      described_class.perform_now
      expect(occ.reload.status).to eq("missed")
    end

    it "leaves an occurrence still inside the grace window pending" do
      occ = occurrence_at(30.minutes.ago)
      described_class.perform_now
      expect(occ.reload.status).to eq("pending")
    end

    # The mark window is generous so a queue outage doesn't skip occurrences
    # forever and the dashboard counts stay honest, even though we won't email
    # about a days-old dose.
    it "still marks a days-old miss that is within the mark lookback" do
      occ = occurrence_at(2.days.ago)
      described_class.perform_now
      expect(occ.reload.status).to eq("missed")
    end

    it "ignores occurrences older than the mark lookback so the first run does not rewrite all history" do
      occ = occurrence_at(8.days.ago)
      described_class.perform_now
      expect(occ.reload.status).to eq("pending")
    end

    it "does not touch an already-acknowledged occurrence" do
      occ = occurrence_at(90.minutes.ago, status: :acknowledged)
      described_class.perform_now
      expect(occ.reload.status).to eq("acknowledged")
    end
  end

  describe "alerting" do
    it "enqueues a retryable notification for a recently-due medication miss" do
      occ = occurrence_at(90.minutes.ago)
      expect { described_class.perform_now }
        .to have_enqueued_job(ReminderNotificationJob).with(occ.id, "missed")
    end

    # Marked missed for the dashboard, but too stale to be worth an email.
    it "does not alert about a miss older than the notify window" do
      occ = occurrence_at(2.days.ago)
      expect { described_class.perform_now }.not_to have_enqueued_job(ReminderNotificationJob)
      expect(occ.reload.status).to eq("missed")
    end

    it "marks a non-medication occurrence missed but enqueues no notification" do
      occ = occurrence_at(90.minutes.ago, category: :hydration)
      # The sweep still records the state so the dashboard's missed counters are
      # accurate, but only medication misses are worth alerting a caregiver about.
      expect { described_class.perform_now }.not_to have_enqueued_job(ReminderNotificationJob)
      expect(occ.reload.status).to eq("missed")
    end
  end
end
