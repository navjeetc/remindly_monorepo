# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoverageGapNotificationService do
  let(:senior) { create(:user, :senior, name: "Mom") }
  let!(:opted_in)  { create(:user, :caregiver, name: "In",  email: "in@example.com") }
  let!(:opted_out) { create(:user, :caregiver, name: "Out", email: "out@example.com", notify_on_coverage_gaps: false) }

  before do
    CaregiverLink.create!(senior: senior, caregiver: opted_in)
    CaregiverLink.create!(senior: senior, caregiver: opted_out)
    # No CaregiverAvailability records, so every upcoming date is a gap.
  end

  describe ".check_and_notify" do
    it "creates an in-app gap notification only for caregivers who left the alerts on" do
      expect { described_class.check_and_notify(senior) }
        .to change { opted_in.notifications.count }.by(1)
        .and change { opted_out.notifications.count }.by(0)
    end

    it "emails the opted-in caregiver and no one else" do
      expect { described_class.check_and_notify(senior) }
        .to have_enqueued_mail(CoverageGapMailer, :notify_gap)
          .with(hash_including(caregiver: opted_in)).once
    end

    it "does not email a caregiver who opted out" do
      expect { described_class.check_and_notify(senior) }
        .not_to have_enqueued_mail(CoverageGapMailer, :notify_gap)
          .with(hash_including(caregiver: opted_out))
    end

    # This job mailed two hard-bounced addresses every morning for sixteen days,
    # producing 44 failed jobs and aiming a steady trickle of mail at mailboxes
    # that do not exist — from the domain that also carries magic-link logins.
    # Postmark refuses these sends anyway, so the only thing attempting them
    # bought was the reputation damage.
    context "when a caregiver's address has hard bounced" do
      let!(:bounced) do
        create(:user, :caregiver, name: "Gone", email: "gone@example.com",
          email_undeliverable_at: 1.day.ago).tap do |caregiver|
          CaregiverLink.create!(senior: senior, caregiver: caregiver)
        end
      end

      it "does not email them" do
        expect { described_class.check_and_notify(senior) }
          .not_to have_enqueued_mail(CoverageGapMailer, :notify_gap)
            .with(hash_including(caregiver: bounced))
      end

      # Their email being dead is no reason to hide the gap from them inside the
      # app, where they can still see it.
      it "still creates their in-app notification" do
        expect { described_class.check_and_notify(senior) }
          .to change { bounced.notifications.count }.by(1)
      end

      it "still emails everyone else" do
        expect { described_class.check_and_notify(senior) }
          .to have_enqueued_mail(CoverageGapMailer, :notify_gap)
            .with(hash_including(caregiver: opted_in)).once
      end
    end
  end

  describe ".notify_gap_filled" do
    let(:date) { Date.new(2026, 8, 6) }

    def stale_gap_notice_for(caregiver)
      Notification.create!(
        user: caregiver,
        notification_type: Notification::TYPES[:coverage_gap],
        title: "Coverage gaps", message: "gap",
        metadata: { senior_id: senior.id, gap_dates: [ date.to_s ] }
      )
    end

    it "sends a gap-filled notice to opted-in caregivers" do
      expect { described_class.notify_gap_filled(senior, date) }
        .to change { opted_in.notifications.where(notification_type: Notification::TYPES[:coverage_filled]).count }.by(1)
    end

    # Even someone who opted out after previously getting alerts should have their
    # now-outdated gap notice cleared — they just don't get a new one.
    it "clears an opted-out caregiver's stale gap notice but sends them no new notice" do
      stale = stale_gap_notice_for(opted_out)

      expect { described_class.notify_gap_filled(senior, date) }
        .to change { stale.reload.read_at }.from(nil)

      expect(opted_out.notifications.where(notification_type: Notification::TYPES[:coverage_filled]).count).to eq(0)
    end
  end
end
