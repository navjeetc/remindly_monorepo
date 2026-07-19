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
  # It uses its own layout: the dashboard one pulls Tailwind from a CDN, roughly
  # 400KB of JavaScript, on the single page most likely to be a first impression
  # and the only one search engines are allowed to index.
  def home
    return redirect_to dashboard_path if current_user

    render layout: "marketing"
  end

  def how_to
  end

  private

  def drop_analytics_cookies_for_anonymous_visitors
    return if current_user

    cookies.delete(:ahoy_visit)
    cookies.delete(:ahoy_visitor)
  end
end
