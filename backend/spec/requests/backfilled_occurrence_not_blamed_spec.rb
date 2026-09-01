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
# Nobody was asked. Remindly declined to ask, deliberately, and the occurrence
# existed for fifty-nine minutes, every one of them after its due time. The miss
# was manufactured by the caregiver's own edit and then reported back to them as
# the care receiver's failing.
RSpec.describe "A reminder edited to a time that has already passed", type: :request do
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

  # The shape the production row had: written now, dated an hour ago.
  def backfilled_occurrence
    Occurrence.create!(reminder: reminder, scheduled_at: 1.hour.ago, status: :pending)
  end

  describe "the decision not to call" do
    it "is recorded, not merely taken" do
      occurrence = backfilled_occurrence

      VoiceReminderSchedulerJob.new.perform

      expect(occurrence.reload.call_suppressed_at).to be_present
      expect(occurrence.call_suppressed_reason).to eq("added_after_its_time")
    end

    # The job takes its clock as an argument, and every decision it makes should
    # be dated by that clock. The outside_calling_hours suppression beside this
    # one already does.
    it "dates the refusal by the clock the run was given" do
      occurrence = backfilled_occurrence
      # Ten minutes, not hours: the scheduler only looks back LOOKBACK from the
      # clock it is given, so a distant simulated time puts the occurrence out of
      # scope and the example passes by never reaching the code.
      simulated = 10.minutes.from_now

      VoiceReminderSchedulerJob.new.perform(now: simulated)

      expect(occurrence.reload.call_suppressed_at).to be_within(1.second).of(simulated)
    end

    it "still places no call, which was always right" do
      backfilled_occurrence

      expect { VoiceReminderSchedulerJob.new.perform }.not_to change(TelnyxCall, :count)
    end

    # The scheduler sees the same row on every run for up to LOOKBACK. The first
    # refusal is the one worth dating.
    it "keeps the first refusal when the scheduler comes round again" do
      occurrence = backfilled_occurrence

      VoiceReminderSchedulerJob.new.perform
      first = occurrence.reload.call_suppressed_at

      VoiceReminderSchedulerJob.new.perform

      expect(occurrence.reload.call_suppressed_at).to eq(first)
    end
  end

  describe "what the caregiver is told" do
    it "does not say the care receiver failed to mark it done" do
      occurrence = backfilled_occurrence
      VoiceReminderSchedulerJob.new.perform

      mail = ReminderActivityMailer.with(
        caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
      ).missed

      body = mail.html_part&.body.to_s + mail.text_part&.body.to_s + mail.body.to_s

      expect(body).not_to include("has not marked")
      expect(body).not_to include("hasn't marked")
    end

    it "says instead that nobody was asked, and why" do
      occurrence = backfilled_occurrence
      VoiceReminderSchedulerJob.new.perform

      mail = ReminderActivityMailer.with(
        caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
      ).missed
      body = (mail.html_part&.body.to_s + mail.text_part&.body.to_s + mail.body.to_s).gsub(/\s+/, " ")

      expect(body).to include("was never asked about this one")
      expect(body).to match(/added to the schedule after that time had already passed/)
    end

    # The subject is the whole message for anybody reading an inbox list or a
    # phone notification, and it was the last place still saying she failed.
    # Fixing the body alone would have left the accusation in the only line most
    # people actually read.
    it "does not accuse in the subject line either" do
      occurrence = backfilled_occurrence
      VoiceReminderSchedulerJob.new.perform

      mail = ReminderActivityMailer.with(
        caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
      ).missed

      expect(mail.subject).not_to include("No confirmation")
      expect(mail.subject).to eq("Remindly didn't call Nora about take bp meds")
    end

    # The HTML mail carries this outside the branches, so every phone failure
    # gets it; the text mail repeats it per branch, and a new branch silently
    # loses it. It is the sentence that separates "not asked" from "not done",
    # which is the entire point of this change.
    it "tells a text-only reader that nothing was asked, not that nothing was done" do
      occurrence = backfilled_occurrence
      VoiceReminderSchedulerJob.new.perform

      mail = ReminderActivityMailer.with(
        caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
      ).missed
      text = (mail.text_part&.body.to_s.presence || mail.body.to_s).gsub(/\s+/, " ")

      expect(text).to include("Nobody was contacted")
      expect(text).to include("says nothing about whether Nora did it")
    end

    # The generic phone_failure branch blames the calling-hours window, which is
    # true of a 3am dose and false here. A row refused for one reason must not
    # borrow another reason's sentence.
    it "does not blame the calling hours, which had nothing to do with it" do
      occurrence = backfilled_occurrence
      VoiceReminderSchedulerJob.new.perform

      mail = ReminderActivityMailer.with(
        caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence.reload
      ).missed
      body = mail.html_part&.body.to_s + mail.text_part&.body.to_s + mail.body.to_s

      expect(body).not_to include("outside the hours")
    end
  end
end
