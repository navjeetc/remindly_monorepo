require 'rails_helper'

RSpec.describe "Acknowledgements", type: :request do
  # The voice web client authenticates with a Bearer token and sends no CSRF
  # token. When this controller inherited from WebController (ActionController::Base
  # with protect_from_forgery), every POST failed with 422 before reaching the
  # database — seniors could read reminders but never mark one taken.
  let(:user) { User.create!(email: "senior@example.com", tz: "America/New_York") }
  let(:jwt) { JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i }, ENV.fetch("JWT_SECRET", "dev_secret_change_me"), "HS256") }

  let(:occurrence) do
    reminder = Reminder.create!(user: user, title: "Pill", rrule: "FREQ=DAILY", tz: user.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending)
  end

  def auth_headers = { "Authorization" => "Bearer #{jwt}" }

  describe "POST /acknowledgements" do
    it "accepts a Bearer-authenticated request without a CSRF token" do
      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: auth_headers
      expect(response).to have_http_status(:created)
    end

    it "records the acknowledgement and marks the occurrence acknowledged" do
      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: auth_headers

      expect(occurrence.reload.status).to eq("acknowledged")
      expect(occurrence.acknowledgements.last.kind).to eq("taken")
    end

    it "rejects an unauthenticated request" do
      post "/acknowledgements", params: { occurrence_id: occurrence.id, kind: "taken" }
      expect(response).to have_http_status(:unauthorized)
    end

    # An expired token should log the user out, not produce a forgery error. This
    # returned 422 when CSRF was skipped only for tokens that resolved to a user.
    it "returns 401, not 422, for an invalid Bearer token" do
      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: { "Authorization" => "Bearer not-a-real-jwt" }
      expect(response).to have_http_status(:unauthorized)
    end

    # Skipping CSRF for *any* Authorization header would also disable it for a
    # Basic credential injected by a reverse proxy, which is not this client.
    it "does not skip CSRF protection for a non-Bearer Authorization scheme" do
      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: { "Authorization" => "Basic #{Base64.strict_encode64('user:pass')}" }
      expect(response).not_to have_http_status(:created)
    end

    it "does not let one user acknowledge another user's occurrence" do
      other = User.create!(email: "intruder@example.com", tz: "America/New_York")
      other_jwt = JWT.encode({ uid: other.id, exp: 1.hour.from_now.to_i }, ENV.fetch("JWT_SECRET", "dev_secret_change_me"), "HS256")

      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: { "Authorization" => "Bearer #{other_jwt}" }

      expect(response).to have_http_status(:not_found)
      expect(occurrence.reload.status).to eq("pending")
    end
  end

  # /voice_reminders is the page seniors actually use, and it authenticates with
  # the Rails session rather than a Bearer token. The original fix here moved the
  # controller to ApplicationController, whose current_user only reads the
  # Authorization header — which fixed the JS client and silently broke this one.
  # Nothing covered the session path, so the swap looked green.
  describe "session-authenticated requests (the /voice_reminders page)" do
    def sign_in(user)
      jwt = JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i }, ENV.fetch("JWT_SECRET", "dev_secret_change_me"), "HS256")
      # Mirrors how the dashboard establishes a session after magic-link verify.
      post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
      jwt
    end

    it "accepts a session-authenticated acknowledgement" do
      sign_in(user)
      post "/acknowledgements", params: { occurrence_id: occurrence.id, kind: "taken" }

      expect(response).to have_http_status(:created)
      expect(occurrence.reload.status).to eq("acknowledged")
    end

    it "accepts a session-authenticated snooze" do
      sign_in(user)
      post "/acknowledgements/snooze", params: { occurrence_id: occurrence.id, minutes: 15 }

      expect(response).to have_http_status(:created)
    end

    # A same-origin fetch sends the session cookie alongside the Bearer header, so
    # an expired token must not quietly succeed as whoever owns the session.
    it "rejects an invalid Bearer token even when a valid session exists" do
      sign_in(user)
      post "/acknowledgements",
        params: { occurrence_id: occurrence.id, kind: "taken" },
        headers: { "Authorization" => "Bearer expired-or-invalid" }

      expect(response).to have_http_status(:unauthorized)
      expect(occurrence.reload.status).to eq("pending")
    end
  end

  describe "POST /acknowledgements/snooze" do
    it "accepts a Bearer-authenticated snooze and schedules a new occurrence" do
      expect {
        post "/acknowledgements/snooze",
          params: { occurrence_id: occurrence.id, minutes: 15 },
          headers: auth_headers
      }.to change { occurrence.reminder.occurrences.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(occurrence.reload.status).to eq("acknowledged")
    end
  end
end
