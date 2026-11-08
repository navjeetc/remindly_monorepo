# frozen_string_literal: true

# Asks Stripe what this account is paying for and sets family_until from it.
# A job rather than inside the webhook so a Stripe API hiccup is retried here,
# instead of failing the webhook and waiting for Stripe's own redelivery.
class RefreshFamilyFromStripeJob < ApplicationJob
  queue_as :default
  # One refresh per account at a time. Each reads Stripe and then writes, and
  # two overlapping could write in the wrong order: an older read of an active
  # subscription landing after a newer read of its cancellation. (Codex and
  # Copilot on #227.) The same keyed limit SyncSubscriberToCrmJob uses.
  limits_concurrency to: 1, key: ->(user_id) { user_id }, duration: 5.minutes
  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 8

  def perform(user_id)
    User.find_by(id: user_id)&.refresh_family_from_stripe!
  end
end
