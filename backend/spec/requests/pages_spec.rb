require "rails_helper"

RSpec.describe "Pages", type: :request do
  # Parse rather than string-match so the specs survive formatting and
  # attribute-order changes in the layout.
  def canonical_href
    Nokogiri::HTML(response.body).at_css("link[rel='canonical']")&.[]("href")
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

      # Signing in creates the account but leaves role nil, which lands the user
      # on pending_approval. Saying so up front stops that reading as a failure.
      it "explains that a new account needs approving" do
        get "/"
        expect(response.body).to include("waiting for approval")
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
    it "renders without authentication" do
      get "/how_to"
      expect(response).to have_http_status(:ok)
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
end
