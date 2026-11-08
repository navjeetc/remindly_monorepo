# frozen_string_literal: true

# Stripe tells Remindly that a subscription changed. Every request is checked
# against the signing secret before anything is read from it, and nothing in
# the payload is trusted beyond which account it is about: the job asks Stripe
# what is true now (see User#refresh_family_from_stripe!).
class StripeWebhooksController < ActionController::API
  SUBSCRIPTION_EVENTS = %w[
    customer.subscription.created
    customer.subscription.updated
    customer.subscription.deleted
    customer.subscription.paused
    customer.subscription.resumed
  ].freeze

  def create
    secret = Billing.webhook_secret
    return head :service_unavailable if secret.nil?

    event = Stripe::Webhook.construct_event(request.body.read, request.headers["Stripe-Signature"], secret)
    user = account_for(event)
    RefreshFamilyFromStripeJob.perform_later(user.id) if user

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end

  private

  def account_for(event)
    object = event.data.object

    case event.type
    when "checkout.session.completed"
      # The customer was created before Checkout and stored on the account,
      # so it is found the same way as every other event; client_reference_id
      # is only a cross-check that they agree.
      user = User.find_by(stripe_customer_id: object["customer"])
      user if user && object["client_reference_id"].to_s == user.id.to_s
    when *SUBSCRIPTION_EVENTS
      User.find_by(stripe_customer_id: object["customer"])
    end
  end
end
