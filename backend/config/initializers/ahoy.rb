class Ahoy::Store < Ahoy::DatabaseStore
  # Someone reading a public page has not asked for an account, and logging
  # their IP to find out that a stranger read a marketing page is not worth the
  # record. Everything behind the login is still tracked: that is where the
  # useful signal is, and those visitors have an account with us.
  #
  # This used to be a hardcoded list of four paths, which went stale the moment
  # /faq, /routine_sheet and the blog were added — those pages recorded an IP,
  # referrer and device for every anonymous reader while the privacy policy said
  # public pages were not tracked. Deriving the list from the routes themselves
  # is what stops that happening again the next public page we add.
  def exclude?
    super || public_page? || credential_in_the_path?
  end

  private

  # Endpoints that are not pages at all. STATIC_PATHS is the list of things a
  # person reads, so the sitemap — which only ever exists to be fetched by a
  # machine — is not in it and would otherwise be tracked. Bots are already
  # excluded outside development, but that only helps for crawlers Ahoy
  # recognises as bots.
  MACHINE_PATHS = [ "/sitemap.xml", "/robots.txt" ].freeze

  # PagesController::STATIC_PATHS is the same constant the sitemap is built
  # from, so a page is either public in both places or in neither.
  #
  # Blog posts need a prefix match because their paths are dynamic. Nothing else
  # may be matched by prefix — "/" is in STATIC_PATHS, and every path starts
  # with it.
  # A reminder link puts its credential in the address, and Ahoy records
  # request.original_url as landing_page — so without this every redemption
  # writes a live, non-expiring key into ahoy_visits in plaintext, keeps it
  # indefinitely, and renders it on the admin audit screen. That is a worse
  # place for it than the request log this project already redacts, because a
  # log rotates and a table does not.
  #
  # Not folded into public_page?: /r/ is the opposite of a public page. It is
  # excluded because of what the path carries, not because of who may read it.
  def credential_in_the_path?
    request&.path.to_s.start_with?("/r/")
  end

  def public_page?
    path = request&.path
    return false if path.blank?

    PagesController::STATIC_PATHS.include?(path) ||
      MACHINE_PATHS.include?(path) ||
      path.start_with?("/blog/") ||
      path == "/subscribers"
  end
end

# set to true for JavaScript tracking
Ahoy.api = false

# Since we have both API and web controllers, we'll handle visit tracking manually
# This prevents automatic visit creation on every API request
Ahoy.api_only = false

# Track bots in development for testing, exclude in production
# Rationale: Tracking bot traffic in production can skew analytics and create noise in
# security monitoring. We enable bot tracking only in development to allow testing, but
# disable it in production to ensure data quality.
Ahoy.track_bots = Rails.env.development?

# set to true for geocoding (and add the geocoder gem to your Gemfile)
# we recommend configuring local geocoding as well
# see https://github.com/ankane/ahoy#geocoding
Ahoy.geocode = false

# Visit duration - create new visit after 4 hours of inactivity
Ahoy.visit_duration = 4.hours

# Visitor duration - create a new visitor token after 30 days.
# Two years (the Ahoy default, and what this was) means a cookie that follows
# someone across sessions for longer than most of them will use the product.
# Long enough to recognise a returning caregiver, short enough not to be a
# durable identifier.
Ahoy.visitor_duration = 30.days
