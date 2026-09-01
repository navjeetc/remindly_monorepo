# frozen_string_literal: true

require "rails_helper"

# From production on 2026-08-25. A caregiver edited a reminder at 8:01pm, moving
# it from 4:02pm to 7:02pm. Editing destroys pending occurrences and re-expands,
# and the expansion back-fills the most recent past slot of the day -- so a row
# was written for 7:02pm, an hour after that time had gone.
#
# Remindly correctly refused to telephone about it: #86 will not ring somebody
# about a dose whose moment passed before the row existed. But the refusal was
# not written down, so the missed email fell through to the wording meant for
# the web client and told the caregiver:
#
#   "Jeet hasn't marked take bp meds as done"
#
# Nobody was telephoned. Remindly declined to telephone, deliberately, and the
# occurrence existed for fifty-nine minutes, every one of them after its due
# time. The miss was manufactured by the caregiver's own edit and then reported
# back to them as the care receiver's failing.
#
# In spec/mailers rather than spec/requests: what this pins is what the caregiver
# is told, and it makes no request. Every neighbour of it in spec/requests does.
RSpec.describe "A reminder edited to a time that has already passed" do
  include ActiveSupport::Testing::TimeHelpers

  let(:senior) { create(:user, :senior, :takes_calls, name: "Nora", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Janey") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }
  let(:reminder) { Reminder.create!(user: senior, title: "take bp meds", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }

  # The scheduler returns immediately unless calls are switched on, so without
  # this every example here would pass by never reaching the code under test.
  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
  end

  # The production clock, in Nora's own zone, rather than whatever time the suite
  # happens to run at.
  #
  # It matters that 8:01pm is *inside* calling hours. Left on the wall clock,
  # these examples ran at 3am as often as not, where the calling-hours guard
  # refuses the row first and every assertion below passes with the back-fill
  # check deleted. Pinning the hour is what makes them mean anything.
  def at(hour, minute)
    ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, hour, minute)
  end

  def edited_at = at(20, 1)
  def due_at = at(19, 2)

  # The shape the production row had: written at 8:01pm, dated 7:02pm. Created by
  # travelling rather than by writing created_at, so both timestamps are honest.
  def back_filled_occurrence
    travel_to(edited_at) do
      Occurrence.create!(reminder: reminder, scheduled_at: due_at, status: :pending)
    end
  end

  # The clock is handed to the job rather than frozen around it, which is how the
  # job is written to be driven.
  def run_scheduler(now: edited_at)
    VoiceReminderSchedulerJob.new.perform(now: now)
  end

  def missed_email_for(occurrence)
    ReminderActivityMailer.with(
      caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
    ).missed
  end

  def body_of(mail)
    (mail.html_part&.body.to_s + mail.text_part&.body.to_s + mail.body.to_s).gsub(/\s+/, " ")
  end

  describe "the decision not to call" do
    it "is recorded, not merely taken" do
      occurrence = back_filled_occurrence

      run_scheduler

      expect(occurrence.reload.call_suppressed_at).to be_present
      expect(occurrence.call_suppressed_reason).to eq("added_after_its_time")
    end

    # The job takes its clock as an argument, and every decision it makes should
    # be dated by that clock. The outside_calling_hours suppression beside this
    # one already does.
    it "dates the refusal by the clock the run was given" do
      occurrence = back_filled_occurrence

      run_scheduler(now: edited_at + 10.minutes)

      expect(occurrence.reload.call_suppressed_at).to eq(edited_at + 10.minutes)
    end

    it "still places no call, which was always right" do
      back_filled_occurrence

      expect { run_scheduler }.not_to have_enqueued_job(VoiceReminderJob)
    end

    # The control, and the reason the assertion above is about the queue rather
    # than about TelnyxCall rows. It used to read `not_to change(TelnyxCall,
    # :count)`, which cannot fail: the scheduler only enqueues, the test adapter
    # never runs what it enqueues, and no call row is written by either. It
    # passed for a row that was ringing somebody.
    it "does telephone about the same row when it was written before its time" do
      ordinary = travel_to(due_at - 1.day) do
        Occurrence.create!(reminder: reminder, scheduled_at: due_at, status: :pending)
      end

      expect { run_scheduler }.to have_enqueued_job(VoiceReminderJob).with(ordinary.id)
    end

    # The scheduler sees the same row on every run for up to LOOKBACK. The first
    # refusal is the one worth dating.
    it "keeps the first refusal when the scheduler comes round again" do
      occurrence = back_filled_occurrence

      run_scheduler
      first = occurrence.reload.call_suppressed_at

      run_scheduler(now: edited_at + 1.minute)

      expect(occurrence.reload.call_suppressed_at).to eq(first)
    end
  end

  describe "what the caregiver is told" do
    it "does not say the care receiver failed to mark it done" do
      occurrence = back_filled_occurrence
      run_scheduler

      body = body_of(missed_email_for(occurrence))

      expect(body).not_to include("has not marked")
      expect(body).not_to include("hasn't marked")
    end

    it "says instead that no call was placed, and why" do
      occurrence = back_filled_occurrence
      run_scheduler

      body = body_of(missed_email_for(occurrence))

      expect(body).to include("no call was placed for this one")
      expect(body).to match(/added to the schedule after that time had already passed/)
    end

    # The email may say only what it knows, and what it knows is that the
    # telephone stayed quiet. The screen client announces anything due and
    # unacknowledged today -- back-filled rows included, since nothing there
    # looks at created_at -- and the dashboard lists it with a Done button. So a
    # care receiver sitting in front of her screen was asked, heard it, and did
    # not press Done. Telling her caregiver she was never asked is the same kind
    # of false sentence as the one this whole change exists to stop sending,
    # pointed the other way.
    it "does not claim she was never asked, which the screen client would make untrue" do
      occurrence = back_filled_occurrence
      run_scheduler

      expect(body_of(missed_email_for(occurrence))).not_to include("was never asked")
    end

    # The subject is the whole message for anybody reading an inbox list or a
    # phone notification, and it was the last place still saying she failed.
    # Fixing the body alone would have left the accusation in the only line most
    # people actually read.
    it "does not accuse in the subject line either" do
      occurrence = back_filled_occurrence
      run_scheduler

      subject_line = missed_email_for(occurrence).subject

      expect(subject_line).not_to include("No confirmation")
      expect(subject_line).to eq("Remindly didn't call Nora about take bp meds")
    end

    # The HTML mail carries this outside the branches, so every phone failure
    # gets it; the text mail repeats it per branch, and a new branch silently
    # loses it. It is the sentence that separates "not asked" from "not done",
    # which is the entire point of this change.
    it "tells a text-only reader that nothing was asked, not that nothing was done" do
      occurrence = back_filled_occurrence
      run_scheduler

      mail = missed_email_for(occurrence)
      text = (mail.text_part&.body.to_s.presence || mail.body.to_s).gsub(/\s+/, " ")

      expect(text).to include("Nobody was contacted")
      expect(text).to include("says nothing about whether Nora did it")
    end

    # The generic phone_failure branch blames the calling-hours window, which is
    # true of a 3am dose and false here -- 8:01pm is inside the hours, which is
    # why the clock above is pinned there. A row refused for one reason must not
    # borrow another reason's sentence.
    it "does not blame the calling hours, which had nothing to do with it" do
      occurrence = back_filled_occurrence
      run_scheduler

      expect(body_of(missed_email_for(occurrence))).not_to include("outside the hours")
    end
  end
end
