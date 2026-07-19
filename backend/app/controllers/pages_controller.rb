class PagesController < WebController
  # Public pages - no authentication required
  layout "dashboard"

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
end
