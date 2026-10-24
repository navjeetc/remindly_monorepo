# frozen_string_literal: true

require "rails_helper"

# The "know someone caring for a parent?" line in the emails a caregiver gets
# about a reminder: the moment Remindly has just been useful to them.
RSpec.describe "Referral line in reminder emails", type: :mailer do
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:caregiver) { create(:user, :caregiver, email: "kid@example.com", name: "Jane") }
  let(:other) { create(:user, :caregiver, email: "sib@example.com", name: "Sam") }
  let(:reminder) do
    Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY",
                     tz: senior.tz, critical: true)
  end
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.zone.local(2026, 7, 21, 9, 0), status: :missed) }

  def mail_for(action, **extra)
    ReminderActivityMailer
      .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence, **extra)
      .public_send(action)
  end

  {
    completed: {},
    missed: {},
    unanswered: { attempts_remaining: 1 },
    escalation_accepted: {}
  }.each do |action, extra|
    it "is in the #{action} email, html and text, tagged as a referral" do
      extra = extra.merge(accepted_by: other) if action == :escalation_accepted
      mail = mail_for(action, **extra)

      [ mail.html_part, mail.text_part ].each do |part|
        body = part.decoded
        expect(body).to include("Know someone caring for a parent?")
        expect(body).to include("#{ApplicationHelper::CANONICAL_HOST}/?from=referral")
      end
    end
  end
end
