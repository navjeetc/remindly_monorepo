# frozen_string_literal: true

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
    after_action :count_this_page_view
  end

  private

  # An aggregate tally, so that "did that post send anyone" has an answer. See
  # PageCount for what is and is not recorded — the short version is that no row
  # describes a person, and the user agent and referrer path are read and thrown
  # away rather than stored.
  #
  # Counting happens here rather than in Ahoy on purpose: turning Ahoy back on
  # for these pages would reinstate the visit row and the cookie, which is the
  # thing the concern above exists to prevent.
  def count_this_page_view
    return unless request.get?
    return unless response.successful?

    # What was *served*, not what was asked for. `request.format.html?` looks
    # like the obvious test and is wrong: a client sending `Accept: */*` — curl,
    # a good many crawlers, anything not a browser — resolves to Mime::ALL, so
    # the check returned false while Rails happily rendered the HTML template
    # and returned 200 text/html. That shipped, and counted nothing for a day.
    # The response's own media type is the honest answer, and it still excludes
    # /sitemap.xml, which is the reason this guard exists.
    return unless response.media_type == "text/html"

    PageCount.record!(
      path: request.path,
      referrer: request.referer,
      source: params[:from],
      user_agent: request.user_agent
    )
  rescue StandardError => e
    # A counter is never worth failing a page over. The marketing pages are the
    # ones strangers and search engines see, and a 500 here would cost more than
    # the measurement is worth.
    Rails.logger.warn("PageCount failed for #{request.path}: #{e.class}: #{e.message}")
  end

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
