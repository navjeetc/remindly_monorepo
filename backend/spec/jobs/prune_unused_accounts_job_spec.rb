# frozen_string_literal: true

require "rails_helper"

RSpec.describe PruneUnusedAccountsJob do
  let(:old) { 15.days.ago }

  def account(email, **attrs)
    User.create!(email: email, created_at: old, **attrs)
  end

  it "deletes an account whose sign-in link was never opened, after 14 days" do
    junk = account("bot@fextemp.example")
    described_class.perform_now
    expect(User.exists?(junk.id)).to be(false)
  end

  it "leaves a recent one, so the Monday funnel email still counts it" do
    recent = User.create!(email: "recent@example.com", created_at: 13.days.ago)
    described_class.perform_now
    expect(User.exists?(recent.id)).to be(true)
  end

  it "leaves anyone who signed in, chose a role, or has something in their account" do
    signed_in = account("signed@example.com", first_signed_in_at: old)
    with_role = account("role@example.com", role: :caregiver)
    paying = account("stripe@example.com", stripe_customer_id: "cus_1")
    invited = account("invited@example.com")
    senior = User.create!(name: "Rose", role: :senior, email_undeliverable_at: old, created_at: old)
    CaregiverLink.create!(senior: senior, caregiver: invited, permission: :manage)
    self_signed = account("self@example.com")
    CaregiverLink.generate_pairing_token(senior: self_signed)
    reminded = account("reminded@example.com")
    Reminder.create!(user: reminded, title: "x", rrule: "FREQ=DAILY", tz: "America/New_York")

    described_class.perform_now

    [ signed_in, with_role, paying, invited, senior, self_signed, reminded ].each do |user|
      expect(User.exists?(user.id)).to be(true), "#{user.email || user.name} was deleted"
    end
  end
end
