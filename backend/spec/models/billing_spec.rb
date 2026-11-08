require "rails_helper"

RSpec.describe Billing do
  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:billing).and_return(true)
  end

  around do |example|
    key = Stripe.api_key
    Stripe.api_key = "sk_test_x"
    example.run
  ensure
    Stripe.api_key = key
  end

  it "sells only with the switch, a key and both prices" do
    expect(described_class.enabled?).to be(true)

    allow(FeatureFlag).to receive(:enabled?).with(:billing).and_return(false)
    expect(described_class.enabled?).to be(false)
  end

  it "sells nothing without a key" do
    Stripe.api_key = nil
    expect(described_class.enabled?).to be(false)
  end

  it "sells nothing where a price is missing, as in production before launch" do
    allow(Rails.application).to receive(:config_for).and_call_original
    allow(Rails.application).to receive(:config_for).with(:stripe)
      .and_return({ family_monthly_price: "price_m", family_yearly_price: nil })
    expect(described_class.enabled?).to be(false)
  end

  it "knows only monthly and yearly" do
    expect(described_class.price("monthly")).to eq("price_test_family_monthly")
    expect(described_class.price("weekly")).to be_nil
  end
end
