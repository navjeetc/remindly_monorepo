# frozen_string_literal: true

require "rails_helper"

# On 2026-11-05 a caregiver unlinked the person she had set up. That person had
# no email, so could not sign in, and with no caregiver nobody could change or
# stop their reminders: the daily call rang them three times the next morning.
# Losing the last caregiver now stops the calls at once, and
# SweepUncaredForCareReceiversJob deletes the account after the grace period.
RSpec.describe "A care receiver left without a caregiver", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:daughter) { create(:user, :caregiver) }
  let(:son) { create(:user, :caregiver) }
  let(:rose) { create(:user, :senior, :takes_calls, email: nil, name: "Rose", email_undeliverable_at: Time.current) }

  def link(caregiver, senior = rose, state: :active)
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: state)
  end

  describe "when the last caregiver goes" do
    it "stops the calls and stamps when, for someone who cannot sign in" do
      link(daughter).destroy!

      rose.reload
      expect(rose.left_without_caregiver_at).to be_present
      expect(rose.call_reminders_enabled).to be(false)
      expect(rose.callable_by_phone?).to be(false)
    end

    it "keeps their number, their consent and their reminders" do
      reminder = rose.reminders.create!(title: "Pills", rrule: "FREQ=DAILY", tz: rose.tz)
      link(daughter).destroy!

      rose.reload
      expect(rose.phone_verified_at).to be_present
      expect(rose.call_consent_at).to be_present
      expect(rose.reminders).to eq([ reminder ])
    end

    it "does the same when the caregiver deletes their own account" do
      link(daughter)
      daughter.destroy!

      expect(rose.reload.left_without_caregiver_at).to be_present
    end

    it "leaves alone someone who still has another caregiver" do
      first = link(daughter)
      link(son)
      first.destroy!

      rose.reload
      expect(rose.left_without_caregiver_at).to be_nil
      expect(rose.call_reminders_enabled).to be(true)
    end

    it "leaves alone a care receiver with their own email, who can sign in" do
      mum = create(:user, :senior, :takes_calls, email: "mum@example.com")
      link(daughter, mum).destroy!

      mum.reload
      expect(mum.left_without_caregiver_at).to be_nil
      expect(mum.call_reminders_enabled).to be(true)
    end

    it "does not count an unclaimed invitation as a caregiver" do
      only = link(daughter)
      CaregiverLink.generate_pairing_token(senior: rose)
      only.destroy!

      expect(rose.reload.left_without_caregiver_at).to be_present
    end
  end

  # Codex and Copilot on #225: a verification call still ringing when the last
  # caregiver left, answered with "1", sets call_reminders_enabled back to true.
  describe "a late consent after the last caregiver left" do
    def consent_arrives_late
      # What TelnyxWebhooksController#consent! writes, after the unlink.
      User.where(id: rose.id).update_all(call_reminders_enabled: true, call_consent_at: Time.current)
      rose.reload
    end

    it "does not make them callable again" do
      link(daughter).destroy!
      consent_arrives_late

      expect(rose.call_reminders_enabled).to be(true)
      expect(rose.callable_by_phone?).to be(false)
    end

    it "does not get a reminder call scheduled" do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
      reminder = rose.reminders.create!(title: "Pills", rrule: "FREQ=DAILY", tz: rose.tz)
      now = Time.current.change(sec: 0)
      travel_to(now - 1.day) { Occurrence.create!(reminder: reminder, scheduled_at: now - 1.minute, status: :pending) }
      link(daughter).destroy!
      consent_arrives_late

      expect { VoiceReminderSchedulerJob.new.perform(now: now) }.not_to have_enqueued_job(VoiceReminderJob)
    end
  end

  # Copilot on #225: a caregiver claiming an invitation between the check for
  # "no caregiver" and the write must not leave the account stamped.
  it "lets the database decide, so a caregiver who arrived after a stale read is not stamped" do
    link(daughter)
    allow(rose).to receive(:without_a_caregiver?).and_return(true) # what an earlier read said

    rose.settle_caregiver_state!

    expect(rose.reload.left_without_caregiver_at).to be_nil
    expect(rose.call_reminders_enabled).to be(true)
  end

  it "clears the stamp when a caregiver claims an invitation to them" do
    link(daughter).destroy!
    invitation = CaregiverLink.generate_pairing_token(senior: rose)

    expect(invitation.pair_with(caregiver: son)).to be(true)
    expect(rose.reload.left_without_caregiver_at).to be_nil
  end

  it "does not fail when the care receiver themselves is deleted" do
    link(daughter)

    expect { rose.destroy! }.not_to raise_error
  end

  describe "the Unlink warning" do
    it "applies to the last caregiver of someone who cannot sign in" do
      only = link(daughter)

      expect(rose.left_without_caregiver_by_removing?(only)).to be(true)
    end

    it "does not apply when another caregiver stays" do
      first = link(daughter)
      link(son)

      expect(rose.left_without_caregiver_by_removing?(first)).to be(false)
    end
  end

  describe SweepUncaredForCareReceiversJob do
    it "stamps someone already without a caregiver and stops their calls (the backstop)" do
      rose # no link was ever destroyed, so no callback stamped her

      described_class.perform_now

      rose.reload
      expect(rose.left_without_caregiver_at).to be_present
      expect(rose.call_reminders_enabled).to be(false)
    end

    it "deletes them once the grace period has passed, with their reminders" do
      rose.reminders.create!(title: "Pills", rrule: "FREQ=DAILY", tz: rose.tz)
      link(daughter).destroy!

      travel_to(User::UNCARED_FOR_GRACE.from_now + 1.hour) { described_class.perform_now }

      expect(User.exists?(rose.id)).to be(false)
      expect(Reminder.where(user_id: rose.id)).to be_empty
    end

    it "keeps them until then" do
      link(daughter).destroy!

      travel_to(User::UNCARED_FOR_GRACE.from_now - 1.hour) { described_class.perform_now }

      expect(User.exists?(rose.id)).to be(true)
    end

    it "keeps them if a caregiver came back, even with the old stamp still on them" do
      link(daughter).destroy!
      stale = rose.reload.left_without_caregiver_at
      # A link written without callbacks, so the stamp is not cleared on the way.
      CaregiverLink.insert_all!([ { senior_id: rose.id, caregiver_id: son.id, permission: 1, state: 2,
                                    created_at: Time.current, updated_at: Time.current } ])
      expect(rose.reload.left_without_caregiver_at).to eq(stale)

      travel_to(User::UNCARED_FOR_GRACE.from_now + 1.hour) { described_class.perform_now }

      expect(User.exists?(rose.id)).to be(true)
      expect(rose.reload.left_without_caregiver_at).to be_nil
    end

    it "never touches a care receiver with their own email" do
      mum = create(:user, :senior, email: "mum@example.com")

      travel_to(1.year.from_now) { described_class.perform_now }

      expect(User.exists?(mum.id)).to be(true)
      expect(mum.reload.left_without_caregiver_at).to be_nil
    end

    it "is scheduled daily in production" do
      schedule = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
      expect(schedule.dig("production", "sweep_uncared_for_care_receivers", "class")).to eq("SweepUncaredForCareReceiversJob")
    end
  end
end
