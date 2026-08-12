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

  # Two tests, in order, because either alone gets it wrong.
  #
  # The first version of this was a denylist only, and anything unmatched counted
  # as human. Within two days that had the human figure overstating by roughly
  # two and a half times. Reading the proxy logs showed why — every one of these
  # was being counted as a person:
  #
  #   http://remindly.care/wp-admin/install.php?step=1   (a URL, in the UA field)
  #   Mozilla/5.0 (compatible; NoctraRecon/1.0)
  #   Mozilla/5.0 (compatible; CMS-Checker/1.0; +https://example.com)
  #   NotificationServiceExtension/1012639507 CFNetwork/3860.600.12 Darwin/25.5.0
  #
  # None carries a bot token, and no denylist was ever going to keep up with
  # them. What they do have in common is that none looks like a browser — so the
  # test is now "does this positively identify as a browser", not "does this fail
  # to identify as a crawler".
  #
  # The denylist still has to run first, and bingbot is why:
  #
  #   Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; bingbot/2.0;
  #   +http://www.bing.com/bingbot.htm) Chrome/116.0.1938.76 Safari/537.36
  #
  # A well-behaved crawler advertising itself inside an otherwise complete Chrome
  # user agent would sail through an allowlist on its own.
  BOT_PATTERN = /
    bot | crawl | spider | slurp | search | scrape | scrapy |
    curl | wget | python-requests | httpx | go-http | java\/ | okhttp |
    headless | phantom | puppeteer | playwright | lighthouse |
    monitor | uptime | pingdom | checkly |
    preview | fetch | archiv | facebookexternalhit | whatsapp | telegram
  /xi

  # A product token a real browser puts in its user agent, with a version after
  # it. Every mainstream browser ships at least one: Chrome and everything built
  # on it, Firefox, Safari, and the iOS variants that use their own names because
  # Apple requires the same underlying engine.
  #
  # Deliberately a shape, not a list of names — an unknown browser that follows
  # the convention counts as a person, which is the right way to be wrong. The
  # cost is that a scraper sending a complete, plausible Chrome user agent is
  # indistinguishable from a person here, and no amount of pattern-matching
  # changes that. See "What this still cannot see" in the spec.
  # `Mobile/` earns its place separately from `Safari/`, and getting this wrong
  # would have quietly deleted the visitors we care most about. A link opened
  # inside an iOS app — Facebook's in-app browser, Instagram's, a forum app's —
  # renders in a WKWebView whose user agent often carries **no** Safari token at
  # all:
  #
  #   Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X)
  #   AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;...]
  #
  # That is a person, on a phone, who tapped a link in the Facebook app — which
  # is precisely how the traffic this counter was built to measure arrives.
  #
  # The version must start with a digit. `[\d.]+` alone also matches `Chrome/.`,
  # which is not a version and makes the allowlist easier to fake than the
  # comment above claims.
  BROWSER_PATTERN = %r{
    \b(
      Chrome | CriOS |            # Chrome, and Chrome on iOS
      Firefox | FxiOS |           # Firefox, and Firefox on iOS
      Edg | EdgA | EdgiOS |       # Edge
      OPR |                       # Opera
      Safari |                    # Safari, and anything Chromium-derived
      Mobile |                    # iOS web views, which may carry nothing else
      Trident                     # old Internet Explorer
    )/\d[\d.]*
  }xi

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
    return true if user_agent.blank?      # no UA at all is a script, not a browser
    return true if user_agent.match?(BOT_PATTERN)   # says so itself — believe it

    # Everything else has to look like a browser to be counted as one.
    !user_agent.match?(BROWSER_PATTERN)
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
