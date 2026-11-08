# frozen_string_literal: true

# Selling the Family plan through Stripe: which prices, and whether selling is
# switched on at all. Stripe holds the card and the subscription; Remindly
# holds only the customer id and how long Family runs (users.family_until),
# which the webhook keeps in step. See User::Billable.
module Billing
  INTERVALS = %w[monthly yearly].freeze

  # Shown on the plan page; Stripe's prices are what is charged.
  PRICE_LABELS = { "monthly" => "$9 a month", "yearly" => "$79 a year" }.freeze

  # All of them, so a half-configured environment sells nothing: the switch,
  # a key, both prices, and the webhook secret. Without the secret every
  # webhook is refused, and a payment could never become Family, since only
  # the webhook sets it. (Codex and Copilot on #227.) Production has no prices
  # until launch.
  def self.enabled?
    FeatureFlag.enabled?(:billing) && Stripe.api_key.present? && webhook_secret.present? &&
      INTERVALS.all? { |interval| price(interval).present? }
  end

  def self.price(interval)
    return nil unless INTERVALS.include?(interval.to_s)

    Rails.application.config_for(:stripe)[:"family_#{interval}_price"].presence
  end

  def self.webhook_secret
    Rails.application.credentials.dig(:stripe, :webhook_secret).presence
  end
end
