require "rails_helper"

RSpec.describe Plan do
  include ActiveSupport::Testing::TimeHelpers

  # Paid plans have started. Every example that is about a limit runs here,
  # because during the beta nothing is limited at all.
  def after_launch
    stub_const("Plan::LAUNCHED_ON", Date.current - 1)
  end

  let(:caregiver) { User.create!(email: "cg@example.com", role: :caregiver, name: "Care", tz: "America/New_York") }
  let(:senior) do
    User.create!(name: "Rose", role: :senior, tz: "America/New_York", email_undeliverable_at: Time.current,
                 set_up_by: caregiver)
  end

  before { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active) }

  def reminder(**attrs)
    Reminder.new(user: senior, title: "Take meds", rrule: "FREQ=DAILY", tz: senior.tz,
                 start_time: Time.zone.parse("2026-11-07 13:00"), **attrs)
  end

  describe "during the beta" do
    it "puts everyone on the beta plan, which limits nothing" do
      expect(Plan.beta?).to be(true)
      expect(caregiver.plan).to eq(Plan::BETA)
      expect(senior.care_plan).to eq(Plan::BETA)
      expect(Plan::BETA.to_h.values_at(:parents, :phone_reminders_a_day, :caregivers)).to all(be_nil)
    end

    it "rings for as many reminders as before" do
      5.times { reminder.save! }
      expect(senior.reminders.ringing.count).to eq(5)
    end

    it "keeps three tries at an unanswered call" do
      expect(TelnyxCall.attempts_for(senior)).to eq(TelnyxCall::MAX_ATTEMPTS)
    end
  end

  describe "once paid plans have started" do
    before { after_launch }

    it "is free unless Family runs past now" do
      expect(caregiver.plan).to eq(Plan::FREE)

      caregiver.update!(family_until: 1.day.from_now)
      expect(caregiver.plan).to eq(Plan::FAMILY)

      travel_to(2.days.from_now) { expect(caregiver.plan).to eq(Plan::FREE) }
    end

    it "holds a parent to the best plan in their circle" do
      expect(senior.care_plan).to eq(Plan::FREE)

      helper = User.create!(email: "helper@example.com", role: :caregiver, name: "Helper", family_until: 1.month.from_now)
      CaregiverLink.create!(senior: senior, caregiver: helper, permission: :manage, state: :active)

      expect(senior.care_plan).to eq(Plan::FAMILY)
    end

    describe "phone reminders a day" do
      before { 3.times { reminder.save! } }

      it "refuses a fourth daily phone reminder on the free plan, and says how to keep it" do
        fourth = reminder
        expect(fourth).not_to be_valid
        expect(fourth.errors[:base].first).to include("3 phone reminders", "Ring their phone")
      end

      it "lets the fourth stay on the screen only" do
        expect(reminder(phone_call: false)).to be_valid
      end

      it "refuses turning the ring back on for one over the limit" do
        quiet = reminder(phone_call: false).tap(&:save!)
        quiet.phone_call = true
        expect(quiet).not_to be_valid
      end

      it "still lets a family over the limit change the time of what they have" do
        Reminder.insert_all([ { user_id: senior.id, title: "Old", rrule: "FREQ=DAILY", tz: senior.tz,
                                phone_call: true, created_at: Time.current, updated_at: Time.current } ])
        over = senior.reminders.find_by!(title: "Old")
        expect(over.update(start_time: Time.zone.parse("2026-11-07 15:00"))).to be(true)
      end

      it "counts a weekly reminder only on its day" do
        senior.reminders.destroy_all
        3.times { reminder(rrule: "FREQ=WEEKLY;BYDAY=MO").save! }

        expect(reminder(rrule: "FREQ=WEEKLY;BYDAY=TU")).to be_valid
        expect(reminder(rrule: "FREQ=WEEKLY;BYDAY=MO")).not_to be_valid
        expect(reminder(rrule: "FREQ=DAILY")).not_to be_valid
      end

      it "counts every time a rule rings in a day, not once per reminder" do
        senior.reminders.destroy_all

        expect(reminder(rrule: "FREQ=HOURLY")).not_to be_valid
        expect(reminder(rrule: "FREQ=DAILY;BYHOUR=8,12,18,21")).not_to be_valid
        reminder(rrule: "FREQ=DAILY;BYHOUR=8,12").save!
        expect(reminder).to be_valid
        reminder.save!
        expect(reminder).not_to be_valid
      end

      it "rechecks a weekly reminder moved to a busier day" do
        senior.reminders.destroy_all
        monday = Time.zone.parse("2026-11-09 13:00")
        tuesday = Time.zone.parse("2026-11-10 13:00")
        3.times { reminder(rrule: "FREQ=WEEKLY", start_time: monday).save! }
        moving = reminder(rrule: "FREQ=WEEKLY", start_time: tuesday).tap(&:save!)

        expect(moving.update(start_time: monday)).to be(false)
        expect(moving.update(start_time: tuesday + 2.hours)).to be(true)
      end

      it "lets a family over the limit move a time within the day it rings" do
        Reminder.insert_all([ { user_id: senior.id, title: "Old", rrule: "FREQ=DAILY;BYHOUR=9", tz: senior.tz,
                                phone_call: true, created_at: Time.current, updated_at: Time.current } ])
        over = senior.reminders.find_by!(title: "Old")
        expect(over.update(rrule: "FREQ=DAILY;BYHOUR=10")).to be(true)
        expect(over.update(rrule: "FREQ=DAILY;BYHOUR=10,11")).to be(false)
      end

      it "does not count on Family" do
        caregiver.update!(family_until: 1.month.from_now)
        expect(reminder).to be_valid
      end
    end

    describe "tries at an unanswered call" do
      let(:occurrence) { Occurrence.create!(reminder: reminder.tap(&:save!), scheduled_at: Time.current, status: :pending) }

      before { senior.update_columns(phone: "+15551234567") }

      def try_and_finish(now)
        call = TelnyxCall.reserve(occurrence, senior, now: now)
        call&.update!(status: "hangup", outcome: "no_response", completed_at: now)
        call
      end

      it "tries once more on the free plan" do
        now = Time.current
        expect(try_and_finish(now)).to be_present
        expect(try_and_finish(now + 6.minutes)).to be_present
        expect(try_and_finish(now + 12.minutes)).to be_nil
      end

      it "tries twice more on Family" do
        caregiver.update!(family_until: 1.month.from_now)
        now = Time.current
        3.times { |i| expect(try_and_finish(now + (i * 6).minutes)).to be_present }
      end
    end

    describe "parents a caregiver can set up" do
      it "counts the parents they set up and still look after, not those they were invited to" do
        expect(caregiver.parents_set_up_count).to eq(1)
        expect(caregiver.parent_limit_reached?).to be(true)

        inviter = User.create!(email: "inviter@example.com", role: :caregiver, name: "Inviter")
        other_family = User.create!(name: "Ann", role: :senior, email_undeliverable_at: Time.current, set_up_by: inviter)
        CaregiverLink.create!(senior: other_family, caregiver: inviter, permission: :manage)
        CaregiverLink.create!(senior: other_family, caregiver: caregiver, permission: :manage)

        expect(caregiver.parents_set_up_count).to eq(1)
      end

      # Link ids follow when a token was made, not when it was redeemed, so the
      # first to redeem is written down at the moment it happens.
      it "belongs to whoever redeems first, whichever token is older" do
        self_signed = User.create!(email: "ann@example.com", role: :senior, name: "Ann")
        older = CaregiverLink.generate_pairing_token(senior: self_signed)
        newer = CaregiverLink.generate_pairing_token(senior: self_signed)
        first = User.create!(email: "first@example.com", role: :caregiver, name: "First")
        second = User.create!(email: "second@example.com", role: :caregiver, name: "Second")

        newer.pair_with(caregiver: first)
        older.pair_with(caregiver: second)

        expect(self_signed.reload.set_up_by).to eq(first)
        expect(first.parents_set_up_count).to eq(1)
        expect(second.parents_set_up_count).to eq(0)
      end
    end

    describe "caregivers a parent can have" do
      it "stops at two on the free plan" do
        expect(senior.caregiver_limit_reached?).to be(false)
        second = User.create!(email: "second@example.com", role: :caregiver, name: "Second")
        CaregiverLink.create!(senior: senior, caregiver: second, permission: :manage)
        expect(senior.caregiver_limit_reached?).to be(true)
      end

      it "lets a Family caregiver join a full free circle, raising it to Family" do
        CaregiverLink.create!(senior: senior, permission: :manage,
                              caregiver: User.create!(email: "second@example.com", role: :caregiver, name: "Second"))
        family = User.create!(email: "family@example.com", role: :caregiver, name: "Family", family_until: 1.month.from_now)

        expect(senior.caregiver_limit_reached?(joining: family)).to be(false)
      end
    end
  end
end
