require "rails_helper"

RSpec.describe "Pages", type: :request do
  describe "GET /how_to" do
    it "renders without authentication" do
      get "/how_to"
      expect(response).to have_http_status(:ok)
    end

    it "points the canonical URL at www.remindly.care" do
      get "/how_to"
      expect(response.body).to include(
        %(<link rel="canonical" href="https://www.remindly.care/how_to">)
      )
    end

    it "keeps the canonical URL on www.remindly.care when served from the legacy subdomain" do
      get "/how_to", headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }
      expect(response.body).to include(
        %(<link rel="canonical" href="https://www.remindly.care/how_to">)
      )
    end
  end
end
