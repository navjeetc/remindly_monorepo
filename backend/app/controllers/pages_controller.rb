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

  def how_to
  end

  # Legal pages, public to everyone (signed in or not) and served with the light
  # marketing layout rather than the CDN-heavy dashboard one.
  def privacy
    render layout: "marketing"
  end

  def terms
    render layout: "marketing"
  end

  private

  def drop_analytics_cookies_for_anonymous_visitors
    return if current_user

    cookies.delete(:ahoy_visit)
    cookies.delete(:ahoy_visitor)
  end
end
