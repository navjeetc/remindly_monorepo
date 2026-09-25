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
  # Same reasoning as :create, and it applies harder here: the token in the URL
  # is the entire credential for this action, not the session, so a forged
  # cross-site request achieves exactly what holding the token already permits
  # — nothing an attacker could not do by sending the person the link directly.
  skip_forgery_protection only: %i[create confirm_unsubscribe]

  # PublicPage's page-count is a page-view tally for pages someone might read
  # twice, keyed on request.path -- and a signed token is not a page, it is a
  # bearer credential. Recording it would write the live token into
  # page_counts, kept indefinitely and readable on the admin traffic screen,
  # for every fetch including one from a token that never resolved to anyone --
  # so an unauthenticated caller could also grow that table without limit by
  # requesting nonsense tokens. Neither action gets a page view.
  skip_after_action :count_this_page_view, only: %i[unsubscribe confirm_unsubscribe]

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

  # GET only ever looks. A bare GET that deleted on the spot is exactly what a
  # corporate mail scanner or a link prefetcher fetches automatically before
  # anyone reads the message -- see the routes.rb comment on this pair.
  #
  # A live token gets the confirm page; anything else -- unknown, tampered, or
  # already used, since no expiry is set and destroying the row is what makes a
  # token stop verifying -- gets the same terminal page confirm_unsubscribe
  # renders after an actual removal. A person who clicks an old or already-used
  # link wants to hear "you will not hear from us", and that is also the
  # honest answer: whatever should have happened, has.
  def unsubscribe
    @subscriber = Subscriber.find_signed(params[:token], purpose: :unsubscribe)

    if @subscriber
      render :confirm_unsubscribe
    else
      render :unsubscribed
    end
  end

  # The one thing this may do: delete the single row its token names. Reached
  # only by the button on the confirm page above, never by the link in the
  # email itself.
  def confirm_unsubscribe
    Subscriber.find_signed(params[:token], purpose: :unsubscribe)&.destroy

    render :unsubscribed
  end

  private

  # A field hidden from people and irresistible to the crawlers that fill in
  # every input they find. A filled one gets the success page and no record, so
  # the bot has nothing to learn from the response.
  def honeypot_filled? = params[:website].present?
end
