require "rails_helper"

RSpec.describe VoiceReminderSchedulerJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:senior) { create(:user, :senior, :takes_calls, name: "Peter", tz: "America/New_York") }
  let(:reminder) { Reminder.create!(user: senior, title: "Take meds", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }

  def at(hour, zone: "America/New_York")
    ActiveSupport::TimeZone[zone].local(2026, 6, 15, hour, 0)
  end

  # created_at before scheduled_at, because that is what a real occurrence looks
  # like: the recurrence expansion writes it ahead of the time it names. A row
  # written *after* its time is a back-fill, which must not ring a phone — see
  # the spec for that at the bottom of this file.
  def occurrence_at(moment, created: nil)
    Occurrence.create!(reminder: reminder, scheduled_at: moment, status: :pending)
              .tap { |o| o.update_columns(created_at: created || moment - 1.day) }
  end

  def due_at(moment)
    occurrence_at(moment - 1.minute)
  end

  # The feature is off by default, everywhere. These specs are about what
  # happens once it is on; the two below assert that off means off.
  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
  end

  # The outer lock. The inner one is two columns on the senior, and the only way
  # to try this in production is to set them — so the flag has to be able to
  # stop the whole thing without touching user records.
  it "enqueues nothing while the feature flag is off, however due the occurrence is" do
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)
    due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
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
    senior.update!(call_reminders_enabled: false)
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
  # Occurrences do not age out: the missed sweep only looks back seven days, so
  # anything unacknowledged for longer stays pending permanently. One production
  # account had thirty such rows going back six months.
  it "ignores an occurrence that has been pending since long before today" do
    Occurrence.create!(reminder: reminder, scheduled_at: at(10) - 6.months, status: :pending)

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "ignores one that fell outside the window while the queue was backed up" do
    occurrence_at(at(10) - described_class::LOOKBACK - 1.minute)

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "still calls about one delayed within the window, so a brief backlog is survivable" do
    occurrence = occurrence_at(at(10) - described_class::LOOKBACK + 1.minute)

    expect { described_class.new.perform(now: at(10)) }
      .to have_enqueued_job(VoiceReminderJob).with(occurrence.id)
  end

  it "does not call about one that is not due yet" do
    occurrence_at(at(10) + 5.minutes)

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end
  it "enqueues nothing for a senior who has opted out" do
    senior.update!(call_opted_out_at: Time.current)
    due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  it "enqueues nothing for a number that never agreed" do
    senior.update!(call_consent_at: nil)
    due_at(at(10))

    expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
  end

  # Recurrence.expand deliberately back-fills the most recent past slot of the
  # day, so editing a reminder writes a pending row dated earlier today. Right
  # for the dashboard — it keeps a same-day reminder visible after its clock time
  # has passed — and wrong for a telephone, because to the query that row is
  # indistinguishable from one that has just come due.
  #
  # Found in production: a reminder edited from 8:36am to 8:15am at 9:53pm
  # materialised a pending 8:15am occurrence dated that morning. It was outside
  # LOOKBACK by then and nothing rang, but the same edit made at 9pm for an 8pm
  # slot would have telephoned the senior immediately, about a dose whose time
  # had already passed.
  describe "an occurrence back-filled after its time had passed" do
    it "is not called about, however recently it was due" do
      occurrence_at(at(10) - 30.minutes, created: at(10))

      expect { described_class.new.perform(now: at(10)) }.not_to have_enqueued_job(VoiceReminderJob)
    end

    it "is still called about when written a moment late, which is ordinary latency" do
      occurrence = occurrence_at(at(10) - 30.minutes, created: at(10) - 30.minutes + 30.seconds)

      expect { described_class.new.perform(now: at(10)) }
        .to have_enqueued_job(VoiceReminderJob).with(occurrence.id)
    end
  end
end
