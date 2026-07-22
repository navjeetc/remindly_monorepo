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

    # Forgery protection is off in the test environment, so these examples turn it
    # on deliberately. Without that they pass for the wrong reason — the request
    # fails on authentication before CSRF is ever consulted, which proves nothing
    # about whether the skip condition is correct.
    describe "CSRF skip condition" do
      around do |example|
        original = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        begin
          example.run
        ensure
          # Without ensure, anything raising out of the example leaves forgery
          # protection globally enabled and every later spec fails somewhere
          # unrelated to the actual cause.
          ActionController::Base.allow_forgery_protection = original
        end
      end

      it "skips CSRF for a Bearer request, which carries no CSRF token" do
        post "/acknowledgements",
          params: { occurrence_id: occurrence.id, kind: "taken" },
          headers: auth_headers
        expect(response).to have_http_status(:created)
      end

      # A Basic credential injected by a reverse proxy is not this client, and
      # must not disable forgery protection for it.
      it "enforces CSRF for a non-Bearer Authorization scheme" do
        post "/acknowledgements",
          params: { occurrence_id: occurrence.id, kind: "taken" },
          headers: { "Authorization" => "Basic #{Base64.strict_encode64('user:pass')}" }
        expect(response).to have_http_status(:unprocessable_content)
      end

      # RFC 7235 scheme names are case-insensitive.
      it "treats a lowercase bearer scheme as Bearer" do
        post "/acknowledgements",
          params: { occurrence_id: occurrence.id, kind: "taken" },
          headers: { "Authorization" => "bearer #{jwt}" }
        expect(response).to have_http_status(:created)
      end
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

  # The senior UI shows Snooze before the scheduled time, so this is reachable by
  # tapping the button early — not an edge case.
  describe "snoozing never moves a reminder earlier" do
    # Assert the response before parsing it. Without this, an unrelated failure —
    # auth, a routing change — surfaces as a JSON parse error on an error page,
    # which hides what actually broke.
    def snooze!(occ, minutes: nil)
      params = { occurrence_id: occ.id }
      params[:minutes] = minutes unless minutes.nil?
      post "/acknowledgements/snooze", params: params, headers: auth_headers

      expect(response).to have_http_status(:created), "snooze failed: #{response.status} #{response.body}"
      Occurrence.find(JSON.parse(response.body).fetch("snoozed_occurrence_id"))
    end

    it "delays from the scheduled time when snoozed before it is due" do
      future = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 25.minutes.from_now, status: :pending)

      new_occ = snooze!(future, minutes: 10)

      expect(new_occ.scheduled_at).to be_within(5.seconds).of(future.scheduled_at + 10.minutes)
      expect(new_occ.scheduled_at).to be > future.scheduled_at
    end

    it "delays from now when snoozed after it is due" do
      past = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 20.minutes.ago, status: :pending)

      new_occ = snooze!(past, minutes: 10)

      expect(new_occ.scheduled_at).to be_within(5.seconds).of(10.minutes.from_now)
    end

    it "clamps a negative delay to the minimum rather than scheduling earlier" do
      new_occ = snooze!(occurrence, minutes: -30)
      expect(new_occ.scheduled_at).to be > occurrence.scheduled_at
    end

    # Asserting the exact delay, not merely "later". A loose assertion passed while
    # an unparseable value was silently clamping to one minute instead of using the
    # default — the spec agreed with the bug.
    it "uses the default delay when minutes is omitted" do
      future = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 25.minutes.from_now, status: :pending)

      new_occ = snooze!(future)

      expect(new_occ.scheduled_at).to be_within(5.seconds).of(future.scheduled_at + 10.minutes)
    end

    # The target time is deterministic now, so a retried request asks for exactly
    # the same occurrence. Occurrences are unique on (reminder_id, scheduled_at),
    # which would raise RecordNotUnique and return 500 for a snooze that had
    # already succeeded.
    it "is idempotent when the same snooze is retried" do
      future = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 25.minutes.from_now, status: :pending)

      first = snooze!(future, minutes: 10)
      expect(response).to have_http_status(:created)

      expect {
        second = snooze!(future, minutes: 10)
        expect(response).to have_http_status(:created)
        expect(second.id).to eq(first.id)
      }.not_to change { Occurrence.where(reminder_id: occurrence.reminder.id).count }
    end

    # The before-due case was idempotent because the scheduled time anchored the
    # target. After the due time the anchor was Time.current, so every retry
    # computed a later target and created another occurrence.
    it "is idempotent when a snooze is retried after the reminder was due" do
      past = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 20.minutes.ago, status: :pending)

      first = snooze!(past, minutes: 10)

      expect {
        second = snooze!(past, minutes: 10)
        expect(second.id).to eq(first.id)
      }.not_to change { Occurrence.where(reminder_id: occurrence.reminder.id).count }
    end

    it "does not stack up snooze acknowledgements on retry" do
      past = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 20.minutes.ago, status: :pending)

      snooze!(past, minutes: 10)

      expect {
        snooze!(past, minutes: 10)
      }.not_to change { past.acknowledgements.where(kind: :snooze).count }
    end

    it "does not leave an acknowledgement behind when the occurrence cannot be created" do
      future = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 25.minutes.from_now, status: :pending)
      allow(Occurrence).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordInvalid.new(Occurrence.new))

      expect {
        post "/acknowledgements/snooze",
          params: { occurrence_id: future.id, minutes: 10 },
          headers: auth_headers
      }.not_to change { Acknowledgement.count }
    end

    it "uses the default delay when minutes cannot be parsed" do
      future = Occurrence.create!(reminder: occurrence.reminder, scheduled_at: 25.minutes.from_now, status: :pending)

      new_occ = snooze!(future, minutes: "not-a-number")

      expect(new_occ.scheduled_at).to be_within(5.seconds).of(future.scheduled_at + 10.minutes)
    end
  end

  # A senior tapping "taken" is what tells a caregiver the medication was actually
  # taken — the emotional centre of the product. Nothing fired here before.
  describe "caregiver notification on acknowledgement" do
    let!(:caregiver) { User.create!(email: "kid@example.com", role: :caregiver, tz: "America/New_York") }
    let!(:link) { CaregiverLink.create!(senior: user, caregiver: caregiver) }

    it "notifies a linked caregiver when the senior marks a medication reminder taken" do
      expect {
        post "/acknowledgements",
          params: { occurrence_id: occurrence.id, kind: "taken" },
          headers: auth_headers
      }.to change { caregiver.notifications.count }.by(1)

      expect(caregiver.notifications.last.notification_type).to eq(Notification::TYPES[:reminder_acknowledged])
    end

    it "does not notify on a skip" do
      expect {
        post "/acknowledgements",
          params: { occurrence_id: occurrence.id, kind: "skip" },
          headers: auth_headers
      }.not_to change { Notification.count }
    end

    # A double tap, or a retry after the first response was lost, must not send a
    # second notification and email to every caregiver.
    it "notifies only once when the same taken is submitted twice" do
      post "/acknowledgements", params: { occurrence_id: occurrence.id, kind: "taken" }, headers: auth_headers

      expect {
        post "/acknowledgements", params: { occurrence_id: occurrence.id, kind: "taken" }, headers: auth_headers
      }.not_to change { Notification.count }
    end

    # A dose the sweep already marked missed, then taken late, should correct the
    # record and tell caregivers it was completed after all.
    it "notifies when a missed occurrence is taken late" do
      occurrence.update!(status: :missed)

      expect {
        post "/acknowledgements", params: { occurrence_id: occurrence.id, kind: "taken" }, headers: auth_headers
      }.to change { caregiver.notifications.count }.by(1)

      expect(occurrence.reload.status).to eq("acknowledged")
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
