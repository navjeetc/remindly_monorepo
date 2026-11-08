# frozen_string_literal: true

# Asks Stripe what this account is paying for and sets family_until from it.
# A job rather than inside the webhook so a Stripe API hiccup is retried here,
# instead of failing the webhook and waiting for Stripe's own redelivery.
class RefreshFamilyFromStripeJob < ApplicationJob
  queue_as :default
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 8

  def perform(user_id)
    User.find_by(id: user_id)&.refresh_family_from_stripe!
  end
end
