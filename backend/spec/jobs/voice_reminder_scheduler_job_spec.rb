require "rails_helper"

RSpec.describe VoiceReminderSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:senior) { create(:user, :senior, name: "Peter", tz: "America/New_York", phone: "+15551234567", voice_reminders_enabled: true) }
  let(:reminder) { Reminder.create!(user: senior, title: "Take meds", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }

  def at(hour, zone: "America/New_York")
    ActiveSupport::TimeZone[zone].local(2026, 6, 15, hour, 0)
  end

  def due_at(moment)
    Occurrence.create!(reminder: reminder, scheduled_at: moment - 1.minute, status: :pending)
  end

  it "enqueues a call for an occurrence that has come due inside calling hours" do
    occurrence = due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }
      .to have_enqueued_job(VoiceReminderJob).with(occurrence.id)
  end

  # Calling hours are per-person and cannot be a WHERE clause, so this is the
  # check that stops a 2am dose enqueuing a job every minute until the missed
  # sweep claims it.
  it "enqueues nothing at 3am" do
    due_at(at(3))

    expect { described_class.new.perform(now: at(3)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "judges the window in the senior's timezone, not the server's" do
    senior.update!(tz: "America/Los_Angeles")
    due_at(at(10))

    # 10:00 in New York is 07:00 in Los Angeles — an hour before the window opens.
    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "enqueues nothing when the senior's timezone cannot be resolved" do
    due_at(at(10))
    senior.update_column(:tz, "Neverwhere/Nowhere")

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "leaves alone a senior who has not turned voice reminders on" do
    senior.update!(voice_reminders_enabled: false)
    due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "leaves alone a senior with no phone number" do
    senior.update!(phone: nil)
    due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "does not call again for an occurrence already called moments ago" do
    occurrence = due_at(at(10))
    TelnyxCall.create!(
      call_control_id: "call-abc", occurrence: occurrence, user: senior,
      status: "initiated", outcome: "pending", created_at: at(10) - 30.seconds
    )

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end
end
