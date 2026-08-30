# frozen_string_literal: true

require "rails_helper"

# Occurrences used to exist only because somebody opened a page. That was fine
# while Remindly was something you looked at — the visit that created a row was
# the visit that displayed it — and stopped being fine the moment a telephone
# call became the delivery, because delivery now happens with nobody looking.
RSpec.describe ExpandRemindersJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:eastern) { ActiveSupport::TimeZone["America/New_York"] }
  let(:senior) { create(:user, :senior, name: "Mum", tz: "America/New_York") }

  # 2am, so the reminders below are ahead of it and nothing is back-filled.
  around { |example| travel_to(eastern.local(2026, 6, 15, 2, 0)) { example.run } }

  def reminder_at(hour, minute, title: "Take meds")
    senior.reminders.create!(title: title, category: :medication, rrule: "FREQ=DAILY",
                             start_time: eastern.local(2026, 6, 15, hour, minute))
          .tap { |r| r.occurrences.destroy_all }
  end

  it "creates the occurrences nobody's page visit would have created" do
    reminder = reminder_at(8, 15)

    expect { described_class.new.perform }.to change { reminder.occurrences.count }.from(0)
  end

  it "materialises them ahead of their time, so they can still be called about" do
    reminder = reminder_at(8, 15)

    described_class.new.perform

    occurrence = reminder.occurrences.reload.order(:scheduled_at).first
    expect(occurrence.created_at).to be < occurrence.scheduled_at
    expect(occurrence.created_at > occurrence.scheduled_at + VoiceReminderSchedulerJob::BACKFILL_GRACE).to be false
  end

  # The property that makes it a sweep rather than a chain: it does not matter
  # how a reminder came to be missing its occurrences, only that the next run
  # notices. A scheme that created the next occurrence when the previous one
  # resolved would stop for good the first time a link broke — silently, since no
  # occurrence means no call and no missed alert either.
  it "repairs a reminder that has fallen behind, whatever the reason" do
    stranded = reminder_at(9, 0, title: "Fallen behind")
    expect(stranded.occurrences).to be_empty

    described_class.new.perform

    expect(stranded.occurrences.reload).not_to be_empty
  end

  it "covers every reminder, not only the one somebody was looking at" do
    a = reminder_at(8, 15, title: "Morning")
    b = reminder_at(20, 41, title: "Evening")

    described_class.new.perform

    expect(a.occurrences.reload).not_to be_empty
    expect(b.occurrences.reload).not_to be_empty
  end

  it "changes nothing when run again, so the hourly schedule is free" do
    reminder_at(8, 15)
    described_class.new.perform

    expect { described_class.new.perform }.not_to change(Occurrence, :count)
  end

  # Recurrence.expand narrates itself at info — seventeen fixed lines plus one per
  # candidate occurrence and one per row created. Useful while a caregiver saves
  # a reminder; twenty-four times a day for every reminder in the database it
  # buries whatever was worth reading.
  #
  # Asserted on the logger's level during the call rather than by intercepting
  # Rails.logger.info, because stubbing that method catches the call before the
  # level is ever consulted — so the obvious version of this spec passes whether
  # anything is silenced or not.
  it "raises the log level while expanding, so the narration is dropped" do
    reminder_at(8, 15)
    levels = []
    allow(Recurrence).to receive(:expand) { levels << Rails.logger.level }

    described_class.new.perform

    expect(levels).to all(eq(Logger::WARN))
  end

  it "puts the level back afterwards" do
    reminder_at(8, 15)
    before = Rails.logger.level

    described_class.new.perform

    expect(Rails.logger.level).to eq(before)
  end

  # One corrupt rule must not take the rest of the night's reminders with it.
  it "carries on past a reminder it cannot expand" do
    broken = reminder_at(7, 0, title: "Broken")
    broken.update_column(:rrule, "this is not an rrule")
    healthy = reminder_at(8, 15, title: "Healthy")

    expect { described_class.new.perform }.not_to raise_error
    expect(healthy.occurrences.reload).not_to be_empty
  end

  # A bare message on a job that runs unattended is not something anybody can act
  # on a week later; the backtrace is the half that says where.
  it "keeps the backtrace when a reminder cannot be expanded" do
    broken = reminder_at(7, 0, title: "Broken")
    broken.update_column(:rrule, "this is not an rrule")
    logged = []
    allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

    described_class.new.perform

    expect(logged.join).to match(/could not be expanded/)
    expect(logged.join.lines.count).to be > 2
  end
end
