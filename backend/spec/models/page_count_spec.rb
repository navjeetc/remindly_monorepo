require "rails_helper"

RSpec.describe PageCount do
  # A `let` rather than a constant: constants declared in a describe block are
  # defined on Object, and pages_spec.rb already has a BROWSER — a Hash of
  # headers, not a string — so the two collided and this file's tests failed
  # only when the whole suite ran.
  let(:browser) do
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end

  describe ".record!" do
    it "creates a row on the first view and increments it thereafter" do
      3.times { described_class.record!(path: "/faq", user_agent: browser) }

      expect(described_class.count).to eq(1)
      expect(described_class.sole.count).to eq(3)
    end

    it "keeps a separate row per day" do
      described_class.record!(path: "/faq", user_agent: browser, day: Date.new(2026, 8, 1))
      described_class.record!(path: "/faq", user_agent: browser, day: Date.new(2026, 8, 2))

      expect(described_class.pluck(:day, :count)).to match_array(
        [ [ Date.new(2026, 8, 1), 1 ], [ Date.new(2026, 8, 2), 1 ] ]
      )
    end

    # The whole point of the table. If a counter row could be traced to a person
    # it would be an Ahoy visit with extra steps, and the public pages exist not
    # to have those.
    it "stores nothing that identifies a visitor" do
      described_class.record!(
        path: "/faq",
        referrer: "https://www.reddit.com/r/AgingParents/comments/abc/my_mother_forgets/",
        user_agent: browser
      )

      stored = described_class.sole.attributes.values.map(&:to_s).join(" ")

      expect(stored).not_to include("Mozilla")
      expect(stored).not_to include("Chrome")
      expect(stored).not_to match(/\d+\.\d+\.\d+\.\d+/)  # no IP
      expect(described_class.column_names).not_to include("ip", "user_agent", "visitor_token")
    end
  end

  describe "referrer handling" do
    # A referrer path carries whatever the person typed into a search box, and
    # on plenty of sites the name of the thread they were reading. The host is
    # all that is needed to answer "which site sent them".
    it "keeps the host and discards the path and query" do
      described_class.record!(
        path: "/",
        referrer: "https://www.google.com/search?q=mum+forgets+her+tablets",
        user_agent: browser
      )

      expect(described_class.sole.referrer_host).to eq("google.com")
      expect(described_class.sole.referrer_host).not_to include("tablets")
    end

    it "treats www and bare hosts as one site" do
      described_class.record!(path: "/", referrer: "https://www.reddit.com/a", user_agent: browser)
      described_class.record!(path: "/", referrer: "https://reddit.com/b", user_agent: browser)

      expect(described_class.count).to eq(1)
      expect(described_class.sole).to have_attributes(referrer_host: "reddit.com", count: 2)
    end

    it "records an empty host for a direct visit" do
      described_class.record!(path: "/", referrer: nil, user_agent: browser)
      expect(described_class.sole.referrer_host).to eq("")
    end

    it "survives a referrer that is not a URL at all" do
      expect {
        described_class.record!(path: "/", referrer: "http://[not a url", user_agent: browser)
      }.not_to raise_error

      expect(described_class.sole.referrer_host).to eq("")
    end

    # Our own three hostnames are navigation, not referrals, and would otherwise
    # dominate the table that exists to show outside sources.
    it "excludes our own hostnames from the referred scope" do
      described_class.record!(path: "/faq", referrer: "https://www.remindly.care/", user_agent: browser)
      described_class.record!(path: "/faq", referrer: "https://news.ycombinator.com/", user_agent: browser)

      expect(described_class.referred.pluck(:referrer_host)).to eq([ "news.ycombinator.com" ])
    end
  end

  describe "campaign tags" do
    it "records a tag from a link we shared" do
      described_class.record!(path: "/", source: "AgingParents", user_agent: browser)
      expect(described_class.sole.source).to eq("agingparents")
    end

    # The tag comes off a query string, so a stranger can put anything there.
    it "discards a tag that is not one of ours in shape" do
      described_class.record!(path: "/", source: "<script>alert(1)</script>", user_agent: browser)
      described_class.record!(path: "/", source: "a" * 200, user_agent: browser)

      expect(described_class.pluck(:source).uniq).to eq([ "" ])
    end
  end

  describe "bot detection" do
    it "flags crawlers and leaves browsers alone" do
      expect(described_class.bot?("Mozilla/5.0 (compatible; Googlebot/2.1)")).to be(true)
      expect(described_class.bot?("curl/8.4.0")).to be(true)
      expect(described_class.bot?("HeadlessChrome/120.0")).to be(true)
      expect(described_class.bot?(browser)).to be(false)
    end

    # A request with no user agent is a script. Counting it as human would
    # inflate the one number this table exists to report.
    it "treats a missing user agent as automated" do
      expect(described_class.bot?(nil)).to be(true)
      expect(described_class.bot?("")).to be(true)
    end

    it "counts humans and bots separately" do
      described_class.record!(path: "/", user_agent: browser)
      described_class.record!(path: "/", user_agent: "Googlebot/2.1")

      expect(described_class.humans.sum(:count)).to eq(1)
      expect(described_class.bots.sum(:count)).to eq(1)
    end
  end

  describe "bounds" do
    it "truncates an absurdly long path rather than storing it whole" do
      described_class.record!(path: "/#{'a' * 500}", user_agent: browser)
      expect(described_class.sole.path.length).to eq(described_class::MAX_LENGTH)
    end
  end
end
