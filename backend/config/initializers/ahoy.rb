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
    super || public_page?
  end

  private

  # PagesController::STATIC_PATHS is the same constant the sitemap is built
  # from, so a page is either public in both places or in neither.
  #
  # Blog posts need a prefix match because their paths are dynamic. Nothing else
  # may be matched by prefix — "/" is in STATIC_PATHS, and every path starts
  # with it.
  def public_page?
    path = request&.path
    return false if path.blank?

    PagesController::STATIC_PATHS.include?(path) ||
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
