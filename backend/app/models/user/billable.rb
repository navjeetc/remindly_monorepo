# frozen_string_literal: true

# Paying for Family through Stripe. Checkout takes the card and the customer
# portal handles everything after (switching monthly and yearly, a new card,
# invoices, cancelling), so Remindly never sees card details and has no billing
# screens of its own beyond the plan page.
#
# What Remindly keeps is one date: users.family_until, how long the paid plan
# runs. It is never set from what a browser says (the success page proves
# nothing); only from Stripe, read back by refresh_family_from_stripe! when a
# webhook says something changed.
module User::Billable
  extend ActiveSupport::Concern

  # Subscription states in which Family is still being paid for. past_due keeps
  # it while Stripe retries a failed card, rather than switching a family's
  # features off over one declined charge.
  PAYING_STATUSES = %w[active trialing past_due].freeze

  def paying_for_family?
    stripe_customer_id.present? && family_until.present? && family_until.future?
  end

  # The Stripe customer this account pays as, created on first use.
  #
  # Written with a guarded UPDATE so two Checkouts started at once cannot each
  # create a customer and leave the account pointing at one while the other
  # holds the subscription. The loser's customer is left in Stripe, empty.
  def stripe_customer_id!
    return stripe_customer_id if stripe_customer_id.present?

    customer = Stripe::Customer.create(
      email: email, name: display_name,
      metadata: { remindly_user_id: id }
    )
    User.where(id: id, stripe_customer_id: nil).update_all(stripe_customer_id: customer.id, updated_at: Time.current)
    reload.stripe_customer_id
  end

  # A Stripe Checkout page for the Family plan, monthly or yearly.
  def family_checkout_session(interval:, success_url:, cancel_url:)
    Stripe::Checkout::Session.create(
      mode: "subscription",
      customer: stripe_customer_id!,
      client_reference_id: id.to_s,
      line_items: [ { price: Billing.price(interval), quantity: 1 } ],
      subscription_data: { metadata: { remindly_user_id: id } },
      success_url: success_url,
      cancel_url: cancel_url,
      # The Stripe account is Anakhsoft's and its own terms are the account's;
      # the terms that govern Remindly are Remindly's, so they are named here,
      # where the person paying reads them.
      custom_text: {
        submit: {
          message: "Renews automatically until you cancel, which you can do at any time from Remindly. " \
                   "By subscribing you agree to Remindly's [terms](https://www.remindly.care/terms)."
        }
      }
    )
  end

  # Stripe's customer portal: change plan, card, invoices, cancel.
  def billing_portal_session(return_url:)
    Stripe::BillingPortal::Session.create(customer: stripe_customer_id, return_url: return_url)
  end

  # Reads every subscription this customer has from Stripe and sets
  # family_until from them: the latest paid-through date among those still
  # being paid for, else when the last one ended.
  #
  # Read back from Stripe rather than taken from the webhook's payload, so
  # events arriving late or out of order cannot leave a stale answer: whichever
  # runs last asks Stripe what is true now.
  def refresh_family_from_stripe!
    return if stripe_customer_id.blank?

    subscriptions = Stripe::Subscription.list(customer: stripe_customer_id, status: "all", limit: 100).data
    paying = subscriptions.select { |sub| PAYING_STATUSES.include?(sub["status"]) }

    until_ = if paying.any?
      paying.map { |sub| paid_through(sub) }.compact.max
    else
      subscriptions.map { |sub| sub["ended_at"] }.compact.max&.then { |at| Time.zone.at(at) }
    end

    update_columns(family_until: until_, updated_at: Time.current)
  end

  private

  # Where the current period ends. On the subscription's items in current API
  # versions, on the subscription itself in older ones.
  def paid_through(subscription)
    ends = subscription["items"]&.data&.map { |item| item["current_period_end"] }&.compact
    at = ends.presence&.max || subscription["current_period_end"]
    at && Time.zone.at(at)
  end
end
