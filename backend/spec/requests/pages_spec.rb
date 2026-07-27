require "rails_helper"

RSpec.describe "Pages", type: :request do
  # Parse rather than string-match so the specs survive formatting and
  # attribute-order changes in the layout.
  def canonical_href
    Nokogiri::HTML(response.body).at_css("link[rel='canonical']")&.[]("href")
  end

  # Structured data is only worth anything if it parses. A trailing comma or an
  # escaping slip makes search engines drop the whole block silently, and nothing
  # about the rendered page looks wrong when that happens.
  def structured_data
    raw = Nokogiri::HTML(response.body).at_css("script[type='application/ld+json']")&.text
    raw && JSON.parse(raw)
  end

  describe "GET / (marketing homepage)" do
    def doc = Nokogiri::HTML(response.body)

    context "when logged out" do
      it "renders the marketing page instead of redirecting to login" do
        get "/"

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("Caring for a parent")
      end

      # The site previously had no indexable homepage at all: / was
      # dashboard#index behind authenticate!, so it 302'd to /login.
      it "points the canonical URL at the root of www.remindly.care" do
        get "/", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
        expect(doc.at_css("link[rel='canonical']")&.[]("href")).to eq("https://www.remindly.care/")
      end

      it "carries a meta description for search results" do
        get "/"
        expect(doc.at_css("meta[name='description']")&.[]("content")).to be_present
      end

      # /how_to is otherwise an orphan - nothing links to it, so nothing finds it.
      it "links to the guide and to sign in" do
        get "/"

        hrefs = doc.css("a").map { |a| a["href"] }
        expect(hrefs).to include("/how_to")
        expect(hrefs).to include("/login")
      end

      it "offers a way to make contact" do
        get "/"
        expect(doc.css("a").map { |a| a["href"] }).to include("mailto:hello@remindly.care")
      end

      # Onboarding is self-serve now: first sign-in asks which role you are and
      # takes you straight in, so the homepage sets that expectation.
      it "explains the self-serve first-sign-in flow" do
        get "/"
        expect(response.body).to include("asks one question")
      end

      # Excluding the path in Ahoy::Store stops the visit row, but Ahoy still
      # sets its cookies — so an anonymous reader went away carrying a
      # month-long identifier anyway. Half a privacy fix.
      it "leaves no analytics cookie on an anonymous visitor" do
        get "/"

        %w[ahoy_visit ahoy_visitor].each do |name|
          expect(response.cookies[name]).to be_blank, "#{name} was left set"
        end
      end

      # Adding csrf_meta_tags here would touch the session and start issuing a
      # session cookie to every anonymous reader of a public page.
      it "issues no session cookie" do
        get "/"
        expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
      end

      # The dashboard layout loads Tailwind from a CDN. This page is the one
      # search engines index, so it must not block on a third-party request.
      it "loads no third-party assets" do
        get "/"

        external = doc.css("script[src], link[rel='stylesheet']").map { |n| n["src"] || n["href"] }.compact

        # "//cdn.example.com/x.js" fetches over the page's own scheme, so a check
        # for "http" alone would pass while the browser still made the request.
        expect(external.select { |u| u.start_with?("http", "//") }).to be_empty
      end

      # Most people meet this site through a link someone shared. Without an
      # image, every one of those links renders as a bare grey box.
      it "carries a social preview image at an absolute URL on the canonical host" do
        get "/", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

        expect(doc.at_css("meta[property='og:image']")&.[]("content"))
          .to eq("https://www.remindly.care/og-image.png")
        expect(doc.at_css("meta[name='twitter:card']")&.[]("content")).to eq("summary_large_image")
      end

      it "ships the file that og:image points at" do
        expect(Rails.root.join("public", "og-image.png")).to exist
      end

      # The price is the reason for the structured data: it is what lets a search
      # result say "free", which is the fact most likely to earn the click.
      it "declares itself as free software in its structured data" do
        get "/"

        expect(structured_data["@type"]).to eq("SoftwareApplication")
        expect(structured_data.dig("offers", "price")).to eq("0")
      end

      it "says plainly that it costs nothing" do
        get "/"
        expect(response.body).to match(/free to use/i)
      end
    end

    context "when signed in" do
      it "redirects to the dashboard so daily use is unchanged" do
        user = User.create!(email: "caregiver@example.com", tz: "America/New_York", name: "Cara")
        post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

        get "/"
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end

  # The marketing footer is the one place these legal pages are linked from, so
  # nothing finds them if the links are missing.
  describe "footer links from the homepage" do
    it "links to the privacy policy and terms" do
      get "/"
      hrefs = Nokogiri::HTML(response.body).css("footer a").map { |a| a["href"] }
      expect(hrefs).to include("/privacy").and include("/terms")
    end
  end

  describe "GET /privacy" do
    it "renders the privacy policy without authentication" do
      get "/privacy"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Privacy")
    end

    it "points the canonical URL at www.remindly.care even from the legacy subdomain" do
      get "/privacy", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
      expect(canonical_href).to eq("https://www.remindly.care/privacy")
    end

    it "states the deletion-on-request commitment" do
      get "/privacy"
      expect(response.body).to match(/delete/i)
    end

    # The policy says analytics aren't collected on public pages, so this page must
    # not persist an Ahoy visit for an anonymous reader.
    it "records no analytics visit for an anonymous visitor" do
      expect { get "/privacy" }.not_to change { Ahoy::Visit.count }
    end

    # It is the indexable set of pages, so it must not block on a third-party asset.
    it "loads no third-party assets" do
      get "/privacy"
      external = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet']").map { |n| n["src"] || n["href"] }.compact
      expect(external.select { |u| u.start_with?("http", "//") }).to be_empty
    end
  end

  describe "GET /terms" do
    it "renders the terms without authentication" do
      get "/terms"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Terms")
    end

    it "points the canonical URL at www.remindly.care" do
      get "/terms"
      expect(canonical_href).to eq("https://www.remindly.care/terms")
    end

    # The honest centerpiece — Remindly is not a medical device — must be present.
    it "carries the medical disclaimer" do
      get "/terms"
      expect(response.body).to match(/not a medical device/i)
    end

    it "links to the privacy policy" do
      get "/terms"
      expect(Nokogiri::HTML(response.body).css("a").map { |a| a["href"] }).to include("/privacy")
    end

    it "records no analytics visit for an anonymous visitor" do
      expect { get "/terms" }.not_to change { Ahoy::Visit.count }
    end
  end

  describe "GET /how_to" do
    it "renders the guide without authentication" do
      get "/how_to"
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1")&.text.to_s).to include("How to use Remindly")
    end

    # The point of serving this on the marketing layout: no CDN Tailwind, and no
    # session cookie for an anonymous, indexable page.
    it "loads no third-party assets" do
      get "/how_to"
      refs = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact
      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end

    it "issues no session cookie to an anonymous visitor" do
      get "/how_to"
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    # A signed-in user reaching the guide from their dashboard must not see the
    # marketing "Sign in" nav — they get a way back to their dashboard instead.
    it "shows a signed-in user a dashboard link, not a sign-in prompt" do
      user = User.create!(email: "cara@example.com", role: :caregiver, tz: "America/New_York", name: "Cara")
      post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      get "/how_to"
      nav_hrefs = Nokogiri::HTML(response.body).css("header a, footer a").map { |a| a["href"] }
      expect(nav_hrefs).to include(dashboard_path)
      expect(nav_hrefs).not_to include(login_path)
    end

    it "points the canonical URL at www.remindly.care" do
      get "/how_to"
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end

    it "keeps the canonical URL on www.remindly.care when served from the legacy subdomain" do
      get "/how_to", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end

    it "ignores query strings so tracking params don't split the canonical" do
      get "/how_to", params: { utm_source: "newsletter" }
      expect(canonical_href).to eq("https://www.remindly.care/how_to")
    end
  end

  describe "GET /faq" do
    it "renders without authentication" do
      get "/faq"

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("h1").text).to include("Questions")
    end

    it "points the canonical URL at www.remindly.care" do
      get "/faq"
      expect(canonical_href).to eq("https://www.remindly.care/faq")
    end

    # The whole point of the page: rich results for the questions caregivers
    # actually type. Google drops a FAQPage whose questions are not also visible
    # on the page, so both come from one source in the template.
    it "publishes every visible question as FAQPage structured data" do
      get "/faq"

      expect(structured_data["@type"]).to eq("FAQPage")

      asked = structured_data["mainEntity"].map { |q| q["name"] }
      shown = Nokogiri::HTML(response.body).css("h2").map(&:text)

      expect(asked).to all(be_in(shown))
      expect(structured_data["mainEntity"]).to all(include("acceptedAnswer"))
    end

    # Trust is the thing being sold here, and the honest answers are the ones a
    # worried family most needs before handing over their parent's medication
    # schedule. They are also the two most tempting lines to quietly drop.
    it "keeps the answers that are 'no'" do
      get "/faq"

      expect(response.body).to match(/medical device/i)
      expect(response.body).to match(/not a substitute/i)
      expect(response.body).to match(/page have to stay open/i)
    end

    it "issues no session cookie to an anonymous visitor" do
      get "/faq"
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    it "loads no third-party assets" do
      get "/faq"
      refs = Nokogiri::HTML(response.body).css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact
      expect(refs.select { |u| u.start_with?("http", "//") }).to be_empty
    end
  end

  describe "GET /sitemap.xml" do
    it "serves XML at the path robots.txt advertises" do
      get "/sitemap.xml"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/xml")
    end

    # A sitemap on one hostname pointing at pages that claim another as canonical
    # is a conflicting signal, and this app answers on three hostnames.
    it "lists every public page as an absolute URL on the canonical host" do
      get "/sitemap.xml", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      locs = Nokogiri::XML(response.body).css("url loc").map(&:text)
      expected = PagesController::STATIC_PATHS + Post.all.map(&:path)

      expect(locs).to match_array(expected.map { |path| "https://www.remindly.care#{path}" })
    end

    # A post is only worth writing if it can be found, and a new file on disk is
    # the whole of "publishing" here — nothing else has to be remembered.
    it "picks up blog posts from disk without anything else being edited" do
      get "/sitemap.xml"

      locs = Nokogiri::XML(response.body).css("url loc").map(&:text)

      expect(Post.all).not_to be_empty, "no posts on disk, so this proves nothing"
      expect(locs).to include("https://www.remindly.care#{Post.all.first.path}")
    end

    # Listing a page that robots.txt forbids tells a crawler to fetch something
    # it is also told not to, and Search Console reports it as an error.
    it "lists nothing that robots.txt disallows" do
      get "/sitemap.xml"

      disallowed = Rails.root.join("public", "robots.txt").read
        .scan(/^Disallow:\s*(\S+)/).flatten

      listed = Nokogiri::XML(response.body).css("url loc")
        .map { |n| URI.parse(n.text).path }

      # robots.txt matches by prefix, so a rule blocks a path when the rule is a
      # prefix of it — not the other way round. Comparing the other direction
      # passes "/" against every rule and fails on all of them.
      listed.each do |path|
        blocking = disallowed.select { |rule| path.start_with?(rule) }

        expect(blocking).to be_empty,
          "#{path} is in the sitemap but blocked by robots.txt rule(s): #{blocking.join(", ")}"
      end
    end

    it "is advertised in robots.txt" do
      robots = Rails.root.join("public", "robots.txt").read
      expect(robots).to include("Sitemap: https://www.remindly.care/sitemap.xml")
    end
  end
end
