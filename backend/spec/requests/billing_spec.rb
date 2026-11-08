require "rails_helper"

RSpec.describe "Plan & billing page", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  let(:caregiver) { User.create!(email: "cg@example.com", role: :caregiver, name: "Care", tz: "America/New_York") }

  before { sign_in(caregiver) }

  it "does not exist while billing is off" do
    get "/billing"
    expect(response).to have_http_status(:not_found)
  end

  describe "with billing on" do
    before { allow(Billing).to receive(:enabled?).and_return(true) }

    it "shows the plan and both prices" do
      get "/billing"
      expect(response.body).to include("Beta", "$9 a month", "$79 a year")
      expect(response.body).not_to include("Manage billing")
    end

    it "sends a caregiver to Stripe Checkout for the price they chose, as their own customer" do
      allow(Stripe::Customer).to receive(:create).and_return(Stripe::StripeObject.construct_from(id: "cus_new"))
      allow(Stripe::Checkout::Session).to receive(:create).and_return(Stripe::StripeObject.construct_from(url: "https://checkout.stripe.com/c/pay/cs_test_1"))

      post "/billing/checkout", params: { interval: "yearly" }

      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_test_1")
      expect(caregiver.reload.stripe_customer_id).to eq("cus_new")
      expect(Stripe::Checkout::Session).to have_received(:create).with(hash_including(
        mode: "subscription", customer: "cus_new", client_reference_id: caregiver.id.to_s,
        line_items: [ { price: "price_test_family_yearly", quantity: 1 } ]
      ))
    end

    it "refuses an interval that is not on offer" do
      post "/billing/checkout", params: { interval: "weekly" }
      expect(response).to redirect_to(billing_path)
    end

    it "does not sell Family twice" do
      caregiver.update!(stripe_customer_id: "cus_1", family_until: 1.month.from_now)
      expect(Stripe::Checkout::Session).not_to receive(:create)
      post "/billing/checkout", params: { interval: "monthly" }
      expect(flash[:notice]).to include("already on the Family plan")
    end

    it "sends a paying caregiver to the customer portal" do
      caregiver.update!(stripe_customer_id: "cus_1", family_until: 1.month.from_now)
      allow(Stripe::BillingPortal::Session).to receive(:create).and_return(Stripe::StripeObject.construct_from(url: "https://billing.stripe.com/p/session/test_1"))

      post "/billing/portal"

      expect(response).to redirect_to("https://billing.stripe.com/p/session/test_1")
    end

    it "does not trust the return from Checkout" do
      get "/billing", params: { checkout: "done" }
      expect(response.body).to include("as soon as Stripe confirms")
      expect(caregiver.reload.family_until).to be_nil
    end

    it "is for caregivers" do
      senior = User.create!(email: "sr@example.com", role: :senior, name: "Sr")
      sign_in(senior)
      get "/billing"
      expect(response).to redirect_to(dashboard_path)
    end
  end
end
