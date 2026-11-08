# frozen_string_literal: true

# Nil where no key is configured (production until launch, CI), which
# Billing.enabled? reads as "billing is off".
Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key)
