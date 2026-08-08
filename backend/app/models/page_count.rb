# How many times a public page was served, by day, without recording who served
# it to. See the migration for why this exists and why it is shaped this way.
#
# The rule this model exists to keep: nothing here may identify a visitor. No
# IP, no user agent string, no cookie, no id of any kind. What is stored is the
# path, the *host* of the referrer (never the full URL — referrer paths and
# query strings leak search terms and worse), an optional campaign tag, and
# whether the request looked automated. All of it aggregated into a counter
# before it is ever written.
class PageCount < ApplicationRecord
  # Long enough for real paths and referrer hosts, short enough that a hostile
  # or broken client cannot write unbounded rows.
  MAX_LENGTH = 120

  # Campaign tags come from ?from= on a link we shared ourselves, so they are
  # ours to constrain. Anything else is discarded rather than stored, which
  # keeps a stranger from writing arbitrary strings into the table.
  SOURCE_FORMAT = /\A[a-z0-9][a-z0-9_-]{0,39}\z/

  # Coarse on purpose. The question is "did humans arrive", not "which crawler
  # was it", and the user agent is thrown away immediately after this runs.
  # Anything unmatched counts as human, so the human number errs high — the
  # opposite mistake would be to quietly discard real visitors.
  BOT_PATTERN = /
    bot | crawl | spider | slurp | search | scrape | scrapy |
    curl | wget | python-requests | httpx | go-http | java\/ | okhttp |
    headless | phantom | puppeteer | playwright | lighthouse |
    monitor | uptime | pingdom | checkly |
    preview | fetch | archiv | facebookexternalhit | whatsapp | telegram
  /xi

  # Hostnames that are us. A click from the homepage to the FAQ is navigation,
  # not a referral, and lumping the two together buries the handful of rows that
  # answer "where did outside visitors come from".
  #
  # Stored in their www-stripped form, because that is what referrer_host_for
  # writes — the app answers on three hostnames and they should not appear as
  # three different sources.
  INTERNAL_HOSTS = %w[
    remindly.care
    remindly.anakhsoft.com
  ].freeze

  scope :humans, -> { where(bot: false) }
  scope :bots, -> { where(bot: true) }
  scope :since, ->(date) { where(day: date..) }
  scope :referred, -> { where.not(referrer_host: [ "" ] + INTERNAL_HOSTS) }
  scope :tagged, -> { where.not(source: "") }

  # Adds one to today's tally for this combination, creating the row if it is
  # the first of the day.
  #
  # Done as a single INSERT ... ON CONFLICT DO UPDATE rather than find-then-save
  # because two simultaneous requests to the same page are the normal case, and
  # read-modify-write would lose one of them.
  def self.record!(path:, referrer: nil, source: nil, user_agent: nil, day: Date.current)
    now = Time.current

    upsert_all(
      [ {
        day: day,
        path: normalize(path),
        referrer_host: referrer_host_for(referrer),
        source: normalize_source(source),
        bot: bot?(user_agent),
        count: 1,
        created_at: now,
        updated_at: now
      } ],
      unique_by: :index_page_counts_on_dimensions,
      on_duplicate: Arel.sql("count = page_counts.count + 1, updated_at = excluded.updated_at")
    )
  end

  def self.bot?(user_agent)
    return true if user_agent.blank?  # no UA at all is a script, not a browser

    user_agent.match?(BOT_PATTERN)
  end

  # Host only. A referrer's path and query carry the search terms someone typed
  # and, on some sites, their account name — none of which we want and none of
  # which we need to answer "which site sent them".
  def self.referrer_host_for(referrer)
    return "" if referrer.blank?

    host = URI.parse(referrer.to_s).host
    return "" if host.blank?

    # www-stripped so one site is one row, here and for INTERNAL_HOSTS.
    normalize(host.downcase.delete_prefix("www."))
  rescue URI::InvalidURIError
    ""
  end

  def self.normalize_source(source)
    candidate = source.to_s.downcase.strip
    candidate.match?(SOURCE_FORMAT) ? candidate : ""
  end

  def self.normalize(value)
    value.to_s[0, MAX_LENGTH].to_s
  end
  private_class_method :normalize
end
