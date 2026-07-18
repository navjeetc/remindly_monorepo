require "rails_helper"

RSpec.describe "Pages", type: :request do
  # Parse rather than string-match so the specs survive formatting and
  # attribute-order changes in the layout.
  def canonical_href
    Nokogiri::HTML(response.body).at_css("link[rel='canonical']")&.[]("href")
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
