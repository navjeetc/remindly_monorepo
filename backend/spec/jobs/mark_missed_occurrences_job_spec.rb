require "rails_helper"

RSpec.describe MarkMissedOccurrencesJob do
  let(:senior) { create(:user, :senior, name: "Mom") }

  def occurrence_at(scheduled_at, category: :medication, status: :pending)
    reminder = Reminder.create!(user: senior, title: "Metformin", category: category, rrule: "FREQ=DAILY", tz: senior.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: scheduled_at, status: status)
  end

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

  it "ignores the historical backlog older than the lookback window" do
    occ = occurrence_at(2.days.ago)

    described_class.perform_now

    expect(occ.reload.status).to eq("pending")
  end

  it "does not touch an already-acknowledged occurrence" do
    occ = occurrence_at(90.minutes.ago, status: :acknowledged)

    described_class.perform_now

    expect(occ.reload.status).to eq("acknowledged")
  end

  it "notifies caregivers when a medication occurrence is marked missed" do
    occ = occurrence_at(90.minutes.ago)

    expect(ReminderNotificationService).to receive(:notify_missed).with(an_instance_of(Occurrence))

    described_class.perform_now
    expect(occ.reload.status).to eq("missed")
  end

  it "marks a non-medication occurrence missed but does not notify" do
    occ = occurrence_at(90.minutes.ago, category: :hydration)

    # The service itself is the medication gate; the sweep still records the state
    # so the dashboard's missed counters are accurate.
    expect { described_class.perform_now }.not_to have_enqueued_mail(ReminderActivityMailer, :missed)
    expect(occ.reload.status).to eq("missed")
  end
end
