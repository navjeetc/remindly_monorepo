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

    # Was /client/ until that standalone client was retired. The voice client
    # needs a session, which /login/verify establishes; /magic/verify only hands
    # back a JWT, which a browser cannot use on its own.
    it "sends web client requests through the session login" do
      get "/magic/request",
        params: { email: "user@example.com", client: "web" },
        headers: { "HOST" => "remindly.care", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("https://remindly.care/login/verify")
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

  describe "POST /login/magic (dashboard form)" do
    before { ActionMailer::Base.deliveries.clear }

    def magic_link_in_last_email
      mail = ActionMailer::Base.deliveries.last
      mail.body.encoded[%r{https?://[^\s"'<]+}]
    end

    it "uses remindly.care as the magic link host when the dashboard login originates there" do
      post "/login/magic",
        params: { email: "user@example.com" },
        headers: { "HOST" => "remindly.care", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("https://remindly.care/magic/verify")
    end

    it "uses remindly.anakhsoft.com when the dashboard login originates there" do
      post "/login/magic",
        params: { email: "user@example.com" },
        headers: { "HOST" => "remindly.anakhsoft.com", "X-Forwarded-Proto" => "https" }

      expect(magic_link_in_last_email).to start_with("https://remindly.anakhsoft.com/magic/verify")
    end

    it "carries a sign-up begun from \"for my parent\" into the emailed link" do
      post "/login/magic", params: { email: "user@example.com", for: "parent" }

      # The text part: the HTML part escapes & as &amp;, which a query parser
      # reads as a parameter called "amp;for".
      link = ActionMailer::Base.deliveries.last.text_part.decoded[%r{https?://\S+}]
      expect(Rack::Utils.parse_query(URI(link).query)["for"]).to eq("parent")
      expect(response).to redirect_to("/login?for=parent")
    end

    it "leaves an ordinary sign-in link alone" do
      post "/login/magic", params: { email: "user@example.com" }

      expect(URI(magic_link_in_last_email).query).not_to include("for=")
      expect(response).to redirect_to("/login")
    end

    it "keeps the parent start when the email was left blank" do
      post "/login/magic", params: { email: "", for: "parent" }

      expect(response).to redirect_to("/login?for=parent")
    end

    it "passes on nothing it does not recognise" do
      post "/login/magic", params: { email: "user@example.com", for: "admin" }

      expect(URI(magic_link_in_last_email).query).not_to include("for=")
      expect(response).to redirect_to("/login")
    end
  end
end
