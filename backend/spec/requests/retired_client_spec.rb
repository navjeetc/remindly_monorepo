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

    # Old magic links looked like /client/?token=... — a 404 would strand anyone
    # following one from an old email or a bookmark.
    it "redirects a nested path" do
      get "/client/index.html"
      expect(response).to redirect_to("/voice_reminders")
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
      body[%r{https://remindly\.care[^"\s<]*}]
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
