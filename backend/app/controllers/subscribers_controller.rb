# frozen_string_literal: true

# The mailing list signup on the public pages.
class SubscribersController < WebController
  include PublicPage

  # CSRF protection is skipped here, and the reason is worth stating because
  # skipping it is normally wrong.
  #
  # An authenticity token has to be stored in the session, so rendering the form
  # would issue a session cookie to every anonymous reader of every public page
  # — which the marketing layout deliberately avoids, and which pages_spec
  # asserts does not happen.
  #
  # What CSRF protects is a request that the server trusts because it arrived
  # with the victim's cookies. This endpoint has no authentication and does
  # nothing on behalf of whoever sends it: the worst a forged request achieves
  # is adding an address to a list, which anyone can already do with curl. The
  # real abuse here is volume and bots, so that is what is defended against
  # below instead.
  skip_forgery_protection only: :create

  rate_limit to: 5, within: 1.minute, only: :create

  def create
    return render :create, locals: { subscriber: nil } if honeypot_filled?

    subscriber = Subscriber.subscribe(
      email: params[:email],
      source: params[:source].presence
    )

    # Both only for a genuinely new record — a repeat signup is silent, so
    # neither the person nor we get a second copy of anything.
    if subscriber.previously_new_record?
      SubscriberMailer.welcome(subscriber).deliver_later
      SubscriberMailer.new_subscriber(subscriber).deliver_later
    end

    render :create, locals: { subscriber: subscriber },
      status: subscriber.persisted? ? :ok : :unprocessable_entity
  end

  private

  # A field hidden from people and irresistible to the crawlers that fill in
  # every input they find. A filled one gets the success page and no record, so
  # the bot has nothing to learn from the response.
  def honeypot_filled? = params[:website].present?
end
