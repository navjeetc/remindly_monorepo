# Behaviour shared by every page a logged-out stranger can reach: the marketing
# pages, the blog, and the subscribe response.
#
# This started life inside PagesController. The blog needed the same two things
# and the temptation was to copy them — which is how one of the two quietly
# stops applying to half the public pages.
module PublicPage
  extend ActiveSupport::Concern

  included do
    # The dashboard layout pulls Tailwind from a CDN — roughly 400KB of
    # JavaScript — which should not block the pages a first-time visitor and a
    # search engine crawler actually see.
    layout "marketing"

    after_action :drop_analytics_cookies_for_anonymous_visitors
  end

  private

  # Excluding these paths in Ahoy::Store stops the visit row being written, but
  # Ahoy still sets its ahoy_visitor and ahoy_visit cookies, so an anonymous
  # reader of a public page still went away carrying a month-long identifier.
  # Half a privacy fix.
  def drop_analytics_cookies_for_anonymous_visitors
    return if current_user

    cookies.delete(:ahoy_visit)
    cookies.delete(:ahoy_visitor)
  end
end
