module ApplicationHelper
  # Shared styling for the top navigation links. Six links repeated the same long
  # class string with only the active/inactive branch differing, so a change to
  # the nav meant six edits that had to stay in step.
  #
  # Larger text and taller hit areas below the breakpoint: the people using this
  # are often reading it on a phone or tablet.
  NAV_LINK_BASE = "inline-flex items-center px-1 py-2 border-b-2 text-base sm:text-sm font-medium".freeze
  NAV_LINK_ACTIVE = "border-blue-500 text-gray-900".freeze
  NAV_LINK_INACTIVE = "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700".freeze

  # Required rather than defaulting to nil: an optional path meant a bare call
  # silently rendered as permanently inactive, which is how the admin links ended
  # up never highlighting on their own pages.
  #
  # @param path [String] the link target, compared against the current request
  # @return [String] class attribute for a top navigation link
  def nav_link_class(path)
    "#{nav_section_active?(path) ? NAV_LINK_ACTIVE : NAV_LINK_INACTIVE} #{NAV_LINK_BASE}"
  end

  # A nav link stands for a section, not a single URL. Comparing paths exactly
  # left Dashboard unhighlighted on /dashboard/senior/5 and Audit Logs
  # unhighlighted on /admin/audit_logs/5 — the pages someone is most likely to be
  # on when they look up to see where they are.
  #
  # The trailing slash matters: without it "/contact" would also claim
  # "/contacts_export". Root is excluded because every path starts with "/".
  def nav_section_active?(path)
    return request.path == path if path == "/"

    request.path == path || request.path.start_with?("#{path}/")
  end

  # The app answers on remindly.anakhsoft.com, remindly.care and www.remindly.care,
  # so every page is reachable at three URLs. Point search engines at one of them.
  CANONICAL_HOST = "https://www.remindly.care".freeze

  # Canonical URL for the current page, always on CANONICAL_HOST.
  # Query strings are dropped — none of our indexable pages vary by them.
  # @return [String] Absolute canonical URL
  def canonical_url
    "#{CANONICAL_HOST}#{request.path}"
  end

  # The canonical origin on its own, for absolute URLs to things that are not the
  # current page — og:image, sitemap entries. Social scrapers do not resolve
  # relative paths, so those have to be absolute.
  # @return [String] "https://www.remindly.care"
  def canonical_host = CANONICAL_HOST

  # Render a hash as a JSON-LD data block for the :structured_data slot.
  #
  # json_escape handles the one way static structured data can still break a
  # page: a "</script>" appearing inside a string value would end the block
  # early, and everything after it would render as markup. It escapes <, > and &
  # so that cannot happen, which is also why the result is safe to mark
  # html_safe — without that, content_for would escape the quotes and emit
  # invalid JSON that search engines silently drop.
  #
  # @param data [Hash] a schema.org node, with @context already set by the caller
  # @return [ActiveSupport::SafeBuffer] escaped JSON ready to sit inside a script tag
  def json_ld(data)
    json_escape(data.to_json).html_safe
  end

  # Convert UTC time to user's timezone for display
  # @param time [Time, ActiveSupport::TimeWithZone] Time to convert
  # @param user [User] User whose timezone to use
  # @return [ActiveSupport::TimeWithZone] Time in user's timezone
  def in_user_timezone(time, user)
    return time unless time.present?
    return time unless user&.tz.present?

    time.in_time_zone(user.tz)
  end

  # Format time in user's timezone
  # @param time [Time, ActiveSupport::TimeWithZone] Time to format
  # @param format [String] strftime format string
  # @param user [User] User whose timezone to use
  # @return [String] Formatted time string
  def format_user_time(time, format, user)
    return "" unless time.present?
    return time.strftime(format) unless user&.tz.present?

    in_user_timezone(time, user).strftime(format)
  end
end
