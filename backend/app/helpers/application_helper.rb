module ApplicationHelper
  # The app answers on remindly.anakhsoft.com, remindly.care and www.remindly.care,
  # so every page is reachable at three URLs. Point search engines at one of them.
  CANONICAL_HOST = "https://www.remindly.care".freeze

  # Canonical URL for the current page, always on CANONICAL_HOST.
  # Query strings are dropped — none of our indexable pages vary by them.
  # @return [String] Absolute canonical URL
  def canonical_url
    "#{CANONICAL_HOST}#{request.path}"
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
