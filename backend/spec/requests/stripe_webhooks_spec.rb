require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  include ActiveJob::TestHelper

  let(:secret) { "whsec_test_secret" }
  let!(:user) { User.create!(email: "payer@example.com", role: :caregiver, name: "Payer", stripe_customer_id: "cus_123") }

  before { allow(Billing).to receive(:webhook_secret).and_return(secret) }

  def deliver(type, object, sign_with: secret)
    payload = { id: "evt_1", object: "event", type: type, data: { object: object } }.to_json
    timestamp = Time.now.to_i
    signature = Stripe::Webhook::Signature.compute_signature(Time.zone.at(timestamp), payload, sign_with)
    post "/stripe/webhooks", params: payload,
         headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=#{timestamp},v1=#{signature}" }
  end

  it "refreshes the account a subscription event is about" do
    expect {
      deliver("customer.subscription.updated", { object: "subscription", id: "sub_1", customer: "cus_123" })
    }.to have_enqueued_job(RefreshFamilyFromStripeJob).with(user.id)
    expect(response).to have_http_status(:ok)
  end

  it "refreshes after a completed Checkout for the same account" do
    expect {
      deliver("checkout.session.completed", { object: "checkout.session", customer: "cus_123", client_reference_id: user.id.to_s })
    }.to have_enqueued_job(RefreshFamilyFromStripeJob).with(user.id)
  end

  it "ignores a Checkout whose account and customer disagree" do
    expect {
      deliver("checkout.session.completed", { object: "checkout.session", customer: "cus_123", client_reference_id: "999" })
    }.not_to have_enqueued_job(RefreshFamilyFromStripeJob)
  end

  it "refuses a request not signed with the secret" do
    expect {
      deliver("customer.subscription.updated", { customer: "cus_123" }, sign_with: "whsec_someone_else")
    }.not_to have_enqueued_job(RefreshFamilyFromStripeJob)
    expect(response).to have_http_status(:bad_request)
  end

  it "refuses everything while no secret is configured" do
    allow(Billing).to receive(:webhook_secret).and_return(nil)
    deliver("customer.subscription.updated", { customer: "cus_123" })
    expect(response).to have_http_status(:service_unavailable)
  end

  it "answers OK to events it does not use, so Stripe stops resending them" do
    deliver("invoice.paid", { object: "invoice", customer: "cus_123" })
    expect(response).to have_http_status(:ok)
  end
end
