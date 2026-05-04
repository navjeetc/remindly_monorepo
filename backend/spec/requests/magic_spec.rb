require 'rails_helper'

RSpec.describe "Magic link", type: :request do
  describe "POST /magic/request" do
    before { ActionMailer::Base.deliveries.clear }

    def magic_link_in_last_email
      mail = ActionMailer::Base.deliveries.last
      mail.body.encoded[%r{https?://[^\s"'<]+}]
    end

    it "uses remindly.care as the magic link host when the request originates there" do
      get "/magic/request",
        params: { email: "user@example.com" },
        headers: { "HOST" => "remindly.care", "X-Forwarded-Proto" => "https" }

      expect(response).to have_http_status(:ok)
      expect(magic_link_in_last_email).to start_with("https://remindly.care/magic/verify")
    end

    it "uses remindly.anakhsoft.com when the request originates there" do
      get "/magic/request",
        params: { email: "user@example.com" },
        headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("https://remindly.anakhsoft.com/magic/verify")
    end

    it "uses the /client/ path for web client requests" do
      get "/magic/request",
        params: { email: "user@example.com", client: "web" },
        headers: { "HOST" => "remindly.care", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("https://remindly.care/client/")
    end

    it "falls back to the configured base_url when the request host is not allowed" do
      configured = Rails.application.credentials.base_url || ENV.fetch('APP_URL', 'http://localhost:5000')
      configured_url = configured.start_with?('http') ? configured : "https://#{configured}"

      get "/magic/request",
        params: { email: "user@example.com" },
        headers: { "HOST" => "evil.example.com", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("#{configured_url}/magic/verify")
    end
  end
end
