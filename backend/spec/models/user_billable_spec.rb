# frozen_string_literal: true

require "rails_helper"

RSpec.describe User::Billable do
  let(:user) { User.create!(email: "payer@example.com", role: :caregiver, name: "Payer", stripe_customer_id: "cus_123") }
  let(:period_end) { 1.month.from_now.change(usec: 0) }

  def subscription(status:, period_end: nil, ended_at: nil)
    Stripe::StripeObject.construct_from(
      id: "sub_#{SecureRandom.hex(3)}", object: "subscription", status: status, ended_at: ended_at&.to_i,
      items: { object: "list", data: [ { object: "subscription_item", current_period_end: period_end&.to_i } ] }
    )
  end

  def stripe_has(*subscriptions)
    allow(Stripe::Subscription).to receive(:list)
      .with(customer: "cus_123", status: "all", limit: 100)
      .and_return(Stripe::ListObject.construct_from(object: "list", data: subscriptions.map(&:to_hash)))
  end

  it "runs Family to the end of the period being paid for" do
    stripe_has(subscription(status: "active", period_end: period_end))
    user.refresh_family_from_stripe!
    expect(user.reload.family_until).to eq(period_end)
    expect(user.paying_for_family?).to be(true)
  end

  it "keeps Family while Stripe retries a failed card" do
    stripe_has(subscription(status: "past_due", period_end: period_end))
    user.refresh_family_from_stripe!
    expect(user.reload.family_until).to eq(period_end)
  end

  it "ends Family when the subscription ended" do
    ended = 1.hour.ago.change(usec: 0)
    stripe_has(subscription(status: "canceled", ended_at: ended))
    user.refresh_family_from_stripe!
    expect(user.reload.family_until).to eq(ended)
    expect(user.paying_for_family?).to be(false)
  end

  it "reads the subscription's own period end in older API versions" do
    sub = Stripe::StripeObject.construct_from(id: "sub_1", object: "subscription", status: "active",
                                              current_period_end: period_end.to_i, items: { object: "list", data: [] })
    stripe_has(sub)
    user.refresh_family_from_stripe!
    expect(user.reload.family_until).to eq(period_end)
  end

  it "does not ask Stripe about an account that has never paid" do
    user.update!(stripe_customer_id: nil)
    expect(Stripe::Subscription).not_to receive(:list)
    user.refresh_family_from_stripe!
  end

  describe "the beta thank-you" do
    before { stub_const("Plan::LAUNCHED_ON", Date.current - 2) }

    it "is Family while the grant runs, separately from any subscription" do
      user.update!(family_granted_until: 6.months.from_now)
      stripe_has(subscription(status: "canceled", ended_at: 1.hour.ago))
      user.refresh_family_from_stripe!

      expect(user.reload.plan).to eq(Plan::FAMILY)
    end
  end
end
