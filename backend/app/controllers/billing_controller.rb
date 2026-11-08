# frozen_string_literal: true

# The plan page, and the two ways off it to Stripe: Checkout to subscribe to
# Family, the customer portal to manage a subscription. Caregivers only: the
# plan is on the caregiver's account, and a care receiver's reminders follow
# the best plan in their circle.
class BillingController < WebController
  layout "dashboard"

  before_action :authenticate!
  before_action :billing_enabled!
  before_action :caregivers_only!

  def show
    @plan = current_user.plan
    # During the beta everyone is on Beta, but somebody who has paid for
    # Family, or been given it, is told they have Family: "Beta" under
    # "Paid through December 8" reads as though the payment did nothing.
    @plan_name = family_in_hand? ? Plan::FAMILY.name : @plan.name
    flash.now[:notice] = checkout_notice if params[:checkout] == "done"
  end

  def checkout
    interval = params[:interval].to_s
    return redirect_to(billing_path, alert: "Choose monthly or yearly.") unless Billing::INTERVALS.include?(interval)
    # family_in_hand?, not paying_for_family?: a Plan page opened before the
    # beta year was granted still has the buttons, and pressing one must not
    # charge for months that were promised free. (Copilot on #229.)
    return redirect_to(billing_path, notice: "You're already on the Family plan.") if family_in_hand?

    session = current_user.family_checkout_session(
      interval: interval,
      success_url: billing_url(checkout: "done"),
      cancel_url: billing_url
    )
    return redirect_to(billing_path, notice: "You're already on the Family plan.") if session.nil?

    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue Stripe::StripeError => e
    stripe_failed(e)
  end

  def portal
    return redirect_to(billing_path) if current_user.stripe_customer_id.blank?

    session = current_user.billing_portal_session(return_url: billing_url)
    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue Stripe::StripeError => e
    stripe_failed(e)
  end

  private

  def family_in_hand?
    current_user.paying_for_family? || current_user.family_granted_until&.future?
  end

  def billing_enabled!
    head :not_found unless Billing.enabled?
  end

  def caregivers_only!
    redirect_to dashboard_path unless current_user.role_caregiver?
  end

  # The return from Checkout proves nothing: the plan changes when Stripe's
  # webhook says the payment went through, usually within seconds.
  def checkout_notice
    if current_user.paying_for_family?
      "Thank you. You're on the Family plan."
    else
      "Thank you. Your Family plan starts as soon as Stripe confirms the payment, usually within a minute. Refresh this page to see it."
    end
  end

  def stripe_failed(error)
    Rails.logger.error "Stripe request failed for user #{current_user.id}: #{error.class}: #{error.message}"
    redirect_to billing_path, alert: "We couldn't reach our payment provider just now. Please try again in a minute."
  end
end
