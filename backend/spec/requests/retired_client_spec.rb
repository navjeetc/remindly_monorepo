require 'rails_helper'

# The standalone voice client at /client/ was retired: /voice_reminders
# superseded it, nothing linked to it, and it served no production traffic.
# These cover the seams that retiring it touched.
RSpec.describe "retired standalone client", type: :request do
  describe "GET /client/*" do
    it "redirects the bare path to the voice reminders page" do
      get "/client"
      expect(response).to redirect_to("/voice_reminders")
    end

    it "redirects a nested path" do
      get "/client/index.html"
      expect(response).to redirect_to("/voice_reminders")
    end

    # Emails already sent contain /client/?token=... and stay valid for 30
    # minutes. Dropping the token would land the user unauthenticated on
    # /voice_reminders and bounce them to login, so the link would look broken.
    context "with a legacy magic-link token" do
      let(:user) { User.create!(email: "legacy@example.com", tz: "America/New_York", name: "Legacy") }
      let(:token) { user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      # Compare the path and parameters rather than the whole URL: query ordering
      # carries no meaning and varies with how the URL is built.
      it "carries the token through to the session login" do
        get "/client/", params: { token: token }

        redirect = URI.parse(response.headers["Location"])
        expect(redirect.path).to eq("/login/verify")
        expect(Rack::Utils.parse_query(redirect.query)).to eq(
          "token" => token,
          "next" => "voice_reminders"
        )
      end

      it "still signs the user in when followed" do
        get "/client/", params: { token: token }
        follow_redirect!

        expect(response).to redirect_to(voice_reminders_path)
      end
    end
  end

  describe "magic link destination" do
    let(:user) { User.create!(email: "senior@example.com", tz: "America/New_York") }
    let(:token) { user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

    # Decode rather than reading the raw body: quoted-printable soft-wraps long
    # lines with "=\r\n" and escapes "=" as "=3D", so a URL with query parameters
    # is both truncated and mangled in the encoded form.
    def link_for(web:)
      mail = MagicMailer.magic_link_email(user, token, web: web, origin: "https://remindly.care")
      body = (mail.html_part || mail.text_part || mail.body).decoded
      link = body[%r{https://remindly\.care[^"\s<]*}]

      # Fail here rather than letting nil reach the caller, where it surfaces as
      # NoMethodError on include and says nothing about what went wrong.
      raise "no magic link found in email body:\n#{body}" if link.nil?

      link
    end

    # /magic/verify returns a JWT, which a browser cannot use on its own. The
    # voice client needs a session, so web links go through /login/verify.
    it "sends voice-client logins to the session login" do
      expect(link_for(web: true)).to include("/login/verify")
    end

    it "asks to land on the reminders page rather than the dashboard" do
      expect(link_for(web: true)).to include("next=voice_reminders")
    end

    it "leaves the API path alone for non-web clients" do
      expect(link_for(web: false)).to include("/magic/verify")
    end
  end

  describe "GET /login/verify" do
    let(:user) { User.create!(email: "senior@example.com", tz: "America/New_York", name: "Senior") }
    let(:token) { user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

    it "lands on the reminders page when asked" do
      get "/login/verify", params: { token: token, next: "voice_reminders" }
      expect(response).to redirect_to(voice_reminders_path)
    end

    it "lands on the dashboard by default" do
      get "/login/verify", params: { token: token }
      expect(response).to redirect_to(dashboard_path)
    end

    # The destination is chosen from an allowlist of names, not taken as a path.
    # Otherwise anyone could send a real Remindly login link that delivers the
    # user, already signed in, to a site of their choosing.
    it "ignores an arbitrary redirect target" do
      get "/login/verify", params: { token: token, next: "https://evil.example.com" }
      expect(response).to redirect_to(dashboard_path)
    end

    it "ignores a relative path traversal attempt" do
      get "/login/verify", params: { token: token, next: "//evil.example.com" }
      expect(response).to redirect_to(dashboard_path)
    end
  end
end
