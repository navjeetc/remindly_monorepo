class PagesController < WebController
  # Public pages - no authentication required
  layout "dashboard"

  # Excluding these paths in Ahoy::Store stops the visit row being written, but
  # Ahoy still sets its ahoy_visitor and ahoy_visit cookies, so an anonymous
  # reader of a public page still went away carrying a month-long identifier.
  # Half a privacy fix. Drop them for visitors who are not signed in.
  after_action :drop_analytics_cookies_for_anonymous_visitors

  # The marketing homepage. Signed-in users go straight to their dashboard, so
  # daily use is unchanged and only logged-out visitors — and search engines —
  # see the marketing page.
  #
  # It uses the marketing layout (like the other public pages here — privacy,
  # terms): the dashboard one pulls Tailwind from a CDN, roughly 400KB of
  # JavaScript, which shouldn't block the pages a first-time visitor and search
  # engines actually see.
  def home
    return redirect_to dashboard_path if current_user

    render layout: "marketing"
  end

  # Served with the light marketing layout (like home, privacy, terms): inlined
  # CSS instead of ~400KB of CDN Tailwind, and no csrf_meta_tags — so an anonymous
  # reader of this public, indexable page gets no session cookie and no
  # third-party request.
  def how_to
    render layout: "marketing"
  end

  # Legal pages, public to everyone (signed in or not) and served with the light
  # marketing layout rather than the CDN-heavy dashboard one.
  def privacy
    render layout: "marketing"
  end

  def terms
    render layout: "marketing"
  end

  # Answers the questions people type into a search engine before they know a
  # product like this exists ("how do I remind my mother to take her tablets").
  # Those searches never match a homepage; they match a page that asks the
  # question back.
  def faq
    render layout: "marketing"
  end

  # Every public page, in the order a person would meet them. This is also the
  # authoritative list of what is indexable: robots.txt disallows everything
  # else, so a page missing here is a page search engines have no route to
  # except an inbound link.
  PUBLIC_PATHS = %w[/ /how_to /faq /privacy /terms].freeze

  # Rendered rather than a static file so it cannot drift from the routes.
  # No layout — a sitemap is XML, and the marketing layout would wrap it in HTML.
  def sitemap
    render "sitemap", formats: :xml, layout: false
  end

  private

  def drop_analytics_cookies_for_anonymous_visitors
    return if current_user

    cookies.delete(:ahoy_visit)
    cookies.delete(:ahoy_visitor)
  end
end
