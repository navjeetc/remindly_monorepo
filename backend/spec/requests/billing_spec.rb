# frozen_string_literal: true

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

    describe "once paid plans have started" do
      before { stub_const("Plan::LAUNCHED_ON", Date.current - 2) }

      it "shows a caregiver on the Free plan what it includes, and Family's prices" do
        get "/billing"
        expect(response.body).to include("Free", "One parent, up to 3 phone reminders a day", "$9 a month", "$79 a year")
      end

      it "does not ask somebody given the beta year to pay for it" do
        caregiver.update!(family_granted_until: 6.months.from_now)
        get "/billing"
        expect(response.body).to include("Family", "as thanks for joining during the beta")
        expect(response.body).not_to include("Family, $9 a month")
      end
    end

    def stripe_lists(subscriptions: [], open_sessions: [])
      allow(Stripe::Subscription).to receive(:list)
        .and_return(Stripe::ListObject.construct_from(object: "list", data: subscriptions))
      allow(Stripe::Checkout::Session).to receive(:list)
        .and_return(Stripe::ListObject.construct_from(object: "list", data: open_sessions))
      allow(Stripe::Checkout::Session).to receive(:expire)
    end

    it "does not start a checkout for somebody who has the beta year, from a page opened before it" do
      caregiver.update!(family_granted_until: 6.months.from_now)
      allow(Stripe::Checkout::Session).to receive(:create)

      post "/billing/checkout", params: { interval: "monthly" }

      expect(response).to redirect_to("/billing")
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end

    it "sends a caregiver to Stripe Checkout for the price they chose, as their own customer" do
      stripe_lists
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

    # Two tabs, or a Checkout left open: only the newest page can be paid.
    it "expires a Checkout page the caregiver still has open before opening another" do
      caregiver.update!(stripe_customer_id: "cus_1")
      stripe_lists(open_sessions: [ { id: "cs_old", object: "checkout.session" } ])
      allow(Stripe::Checkout::Session).to receive(:create).and_return(Stripe::StripeObject.construct_from(url: "https://checkout.stripe.com/c/pay/cs_new"))

      post "/billing/checkout", params: { interval: "monthly" }

      expect(Stripe::Checkout::Session).to have_received(:expire).with("cs_old")
      expect(response).to redirect_to("https://checkout.stripe.com/c/pay/cs_new")
    end

    # Paid a moment ago, before the webhook has written family_until.
    it "asks Stripe, not only family_until, before selling Family again" do
      caregiver.update!(stripe_customer_id: "cus_1")
      period_end = 1.month.from_now.to_i
      stripe_lists(subscriptions: [ { id: "sub_1", object: "subscription", status: "active",
                                      items: { object: "list", data: [ { current_period_end: period_end } ] } } ])
      expect(Stripe::Checkout::Session).not_to receive(:create)

      post "/billing/checkout", params: { interval: "yearly" }

      expect(flash[:notice]).to include("already on the Family plan")
      expect(caregiver.reload.family_until.to_i).to eq(period_end)
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

    it "says Family to somebody who has paid, even during the beta" do
      caregiver.update!(stripe_customer_id: "cus_1", family_until: 1.month.from_now)
      get "/billing"
      expect(response.body).to include("Family", "Paid through")
      expect(response.body).not_to include(">Beta<")
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
