# frozen_string_literal: true

require "rails_helper"

# A reminder link is a capability URL: the secret in the address is the whole
# credential, and the device holding it never signs in. That makes this feature
# a security boundary before it is a convenience, so the specs are as much the
# deliverable as the code — see docs/SENIOR_ACCESS_DESIGN.md, "What the specs
# must assert".
#
# The boundary list below is deliberately enumerated rather than sampled. A
# route added later that forgets link mode exists should fail here.
RSpec.describe "A reminder link", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:care_receiver) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:link) { ReminderLink.mint(user: care_receiver) }

  def redeem(token = link.token) = get "/r/#{token}"

  def reminder_due(at, title: "Take your tablets", user: care_receiver)
    reminder = Reminder.create!(user: user, title: title, rrule: "FREQ=DAILY", tz: user.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: at, status: :pending)
  end

  describe "redeeming one" do
    # Served at the address itself rather than redirected to a tidier one.
    #
    # The bookmark is the credential, and a caregiver bookmarks what the address
    # bar says after they open the page — so a redirect would have them saving a
    # tokenless address that works only while the cookie lives. Six months later
    # the cookies clear and that bookmark lands on a login page: the exact
    # failure this feature exists to end.
    it "shows the reminders at the address that was opened" do
      redeem

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Reminders")
    end

    # The credential is in the address, deliberately. It should still not be
    # printed into the page, where it would end up in a screenshot a caregiver
    # sends someone.
    it "does not print the token into the page" do
      redeem

      expect(response.body).not_to include(link.token)
    end

    it "keeps working at the same address after the cookies are cleared" do
      redeem
      expect(response).to have_http_status(:ok)

      # What a device reset, a cleared browser or a new tablet looks like: the
      # bookmark survives, everything else is gone.
      reset!

      redeem
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Reminders")
    end

    # The cookie is what lets the page poll: the JSON lives at another path,
    # which the bookmarked address does not cover.
    it "leaves the device able to poll" do
      redeem

      get "/voice_reminders/today"

      expect(response).to have_http_status(:ok)
    end

    it "reads that care receiver's reminders" do
      tz = ActiveSupport::TimeZone["America/New_York"]
      travel_to(tz.parse("2026-09-04 09:00")) do
        due = reminder_due(tz.parse("2026-09-04 20:00"))
        redeem

        get "/voice_reminders/today"

        expect(response.parsed_body.map { |o| o["id"] }).to eq([ due.id ])
      end
    end

    # How a caregiver tells a live tablet from one that silently stopped.
    it "records that it was used" do
      expect { redeem }.to change { link.reload.last_used_at }.from(nil)
    end
  end

  # The number the whole panel is for. A device redeems once and then polls for
  # months without touching /r/ again, so recording only at redemption would
  # have the panel reporting "last heard from 3 months ago" about a tablet that
  # had been working the entire time — wrong in the direction that causes a
  # false alarm, about the one thing a caregiver would act on.
  describe "how a live device stays visibly live" do
    it "records the poll, not only the redemption" do
      redeem
      link.reload.update_column(:last_used_at, 3.hours.ago)

      expect {
        get "/voice_reminders/today"
      }.to change { link.reload.last_used_at.to_i }
    end

    it "records the page load too" do
      redeem
      link.reload.update_column(:last_used_at, 3.hours.ago)

      expect { get "/voice_reminders" }.to change { link.reload.last_used_at.to_i }
    end

    # The page polls every few seconds. Writing each one would be a write per
    # poll per device, all day, to say something read in hours.
    it "does not write on every poll" do
      redeem
      recorded = link.reload.last_used_at

      expect {
        3.times { get "/voice_reminders/today" }
      }.not_to change { link.reload.last_used_at.to_i }

      expect(recorded).to be_present
    end
  end

  describe "a token that does not work" do
    it "refuses one nobody ever minted" do
      redeem("not-a-real-token")

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a revoked one" do
      link.revoke!

      redeem

      expect(response).to have_http_status(:not_found)
    end

    # Answered identically, on purpose. A different response for a revoked token
    # tells whoever holds a dead link that it was once real, and tells anybody
    # guessing which guesses were close.
    it "cannot be told apart from one that never existed" do
      link.revoke!
      redeem
      revoked = [ response.status, response.body ]

      redeem("wholly-invented-token")

      expect([ response.status, response.body ]).to eq(revoked)
    end

    it "does not sign anybody in" do
      link.revoke!
      redeem

      get "/voice_reminders"

      expect(response).to redirect_to(login_path)
    end
  end

  # Revocation has to reach a device that already holds the cookie, or it is a
  # gesture rather than a control.
  describe "revoking one already in use" do
    it "stops the device on its next request" do
      redeem
      get "/voice_reminders"
      expect(response).to have_http_status(:ok)

      link.revoke!

      get "/voice_reminders"
      expect(response).to redirect_to(login_path)
    end

    # A status, not a redirect. fetch() follows redirects, so a login page comes
    # back as a 200 full of HTML and the device would go on announcing the
    # reminders it already had — looking exactly as it does when everything
    # works, for as long as the tablet stays on.
    it "stops the polling too" do
      redeem
      link.revoke!

      get "/voice_reminders/today"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("Unauthorized")
    end
  end

  # The enumerated boundary. Everything a link must not reach, listed one route
  # at a time so that a new route which forgets link mode fails here rather than
  # shipping.
  describe "what a link cannot reach" do
    before { redeem }

    {
      "the dashboard" => "/dashboard",
      "the profile" => "/profile",
      "notifications" => "/notifications",
      # The nested path, which is the one that exists: a top-level /tasks is a
      # routing 404 and would have passed this example without ever reaching
      # TasksController.
      "tasks" => "/seniors/%<senior_id>d/tasks",
      "the pairing screen" => "/dashboard/pair",
      "a pairing token" => "/dashboard/generate",
      "the caregiver list" => "/caregiver_links",
      "their own reminders as data" => "/reminders",
      "the reminder form" => "/reminders/new"
    }.each do |name, path|
      it "cannot reach #{name}" do
        get format(path, senior_id: care_receiver.id)

        expect(response).not_to have_http_status(:ok),
          "#{path} answered 200 to a reminder-link cookie"
        expect(response.body).not_to include("Sign Out")
      end
    end

    # The one it would be easiest to leak: a link belongs to one care receiver,
    # and must not become a way to read another's schedule.
    it "cannot read another care receiver's reminders" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")
      tz = ActiveSupport::TimeZone["America/New_York"]

      travel_to(tz.parse("2026-09-04 09:00")) do
        mine = reminder_due(tz.parse("2026-09-04 10:00"))
        reminder_due(tz.parse("2026-09-04 11:00"), title: "Not mine", user: other)

        get "/voice_reminders/today"

        titles = response.parsed_body.map { |o| o["title"] }
        expect(titles).to eq([ "Take your tablets" ])
        expect(response.parsed_body.map { |o| o["id"] }).to eq([ mine.id ])
      end
    end
  end

  # The cookie is read by VoiceRemindersController and nowhere else, so a
  # signed-in caregiver's experience cannot be altered by holding one.
  describe "signing in normally" do
    it "is unaffected by a link cookie being present" do
      redeem
      post "/magic/verify", params: {
        token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }

      get "/dashboard"

      expect(response).to have_http_status(:ok)
    end
  end

  # The page in link mode. Mirrors the assertion the marketing pages carry, for
  # a sharper reason: this is the screen a care receiver looks at all day, on a
  # device chosen for sitting in a kitchen rather than for being fast, and a
  # third-party request here is both a dependency and something to leak to.
  describe "the page it lands on" do
    def doc = Nokogiri::HTML(response.body)

    before { redeem }

    it "loads no third-party assets" do
      external = doc.css("script[src], link[rel='stylesheet'], img[src], iframe[src]")
        .map { |n| n["src"] || n["href"] }.compact

      # "//cdn.example.com/x.js" fetches over the page's own scheme, so checking
      # for "http" alone would pass while the browser still made the request.
      expect(external.select { |u| u.start_with?("http", "//") }).to be_empty
    end

    # Every one of these is a dead end for somebody who has no account, on the
    # screen least able to absorb one.
    it "offers nothing a link holder cannot use" do
      text = doc.text

      expect(text).not_to include("Sign Out")
      expect(text).not_to include("Profile")
      expect(text).not_to include("Back to Remindly")
      expect(doc.css("a[href='#{dashboard_path}']")).to be_empty
    end

    # The document URL is the credential now, and the browser default sends the
    # full URL as Referer on same-origin requests — of which this page makes one
    # every few seconds, forever. Without this the token lands in access logs by
    # a second route, after the first one was closed.
    it "sends the token nowhere as a referrer" do
      expect(doc.at_css("meta[name='referrer']")&.[]("content")).to eq("no-referrer")
    end

    # The settings dialog's own class names — modal, btn-primary and the rest —
    # are the view's, not utilities, and were defined nowhere in the application
    # until this layout. Undefined, the dialog opened as a plain block and Save
    # looked exactly like Reset to Defaults.
    it "styles the dialog the page actually contains" do
      css = doc.at_css("style").text

      %w[.modal .modal-content .modal-footer .btn-primary .btn-secondary .close-btn].each do |rule|
        expect(css).to include(rule), "#{rule} is used by the page and defined nowhere"
      end
    end

    it "keeps itself out of search results" do
      expect(doc.at_css("meta[name='robots']")&.[]("content")).to include("noindex")
    end

    # The text-size setting is the accessibility control that matters most on
    # this screen, and it must survive the layout change.
    it "still scales with the care receiver's text size" do
      care_receiver.update!(text_size: :largest)

      get "/voice_reminders"

      expect(Nokogiri::HTML(response.body).at_css("html")["style"])
        .to include(User::TEXT_SCALES.fetch("largest").to_s)
    end
  end

  # The case this whole feature exists for, and the one that would have got it
  # wrong: the tablet is signed in until it is not. A JWT that has expired is
  # still *present*, so asking whether a session token exists said "signed in"
  # while the session no longer authenticated anything — and the page would then
  # have offered Done and Snooze buttons that the expired credential cannot
  # honour, failing silently on the one screen a care receiver relies on.
  describe "a device whose session has expired underneath it" do
    it "falls back to the link and knows it did" do
      # Signed in for real, then left alone past the JWT's life.
      post "/magic/verify", params: {
        token: care_receiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }
      redeem

      travel(31.days) do
        get "/voice_reminders"

        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML(response.body).text).not_to include("Back to Remindly")
      end
    end

    # And it still shows the reminders rather than a login page, which is the
    # failure the link was built to end.
    it "keeps announcing" do
      post "/magic/verify", params: {
        token: care_receiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }
      redeem
      tz = ActiveSupport::TimeZone["America/New_York"]

      travel(31.days) do
        reminder_due(tz.now + 2.hours)

        get "/voice_reminders/today"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.size).to eq(1)
      end
    end
  end

  # A signed-in care receiver reaches the same page through the nav, and should
  # still have a way back to the rest of the app.
  describe "the page when somebody is signed in" do
    it "offers the way back that link mode does not" do
      post "/magic/verify", params: {
        token: care_receiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }

      get "/voice_reminders"

      expect(response.body).to include("Back to Remindly")
    end
  end

  # The caregiver's side: minting one, seeing whether the device is alive, and
  # ending it. Minting hands out a credential to somebody's reminders, so it
  # sits behind the same permission as writing those reminders.
  describe "the caregiver's panel" do
    let!(:manage_link) do
      CaregiverLink.create!(senior: care_receiver, caregiver: caregiver, permission: :manage)
    end

    def sign_in_caregiver
      post "/magic/verify", params: {
        token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }
    end

    it "mints a link" do
      sign_in_caregiver

      expect {
        post "/dashboard/senior/#{care_receiver.id}/reminder_link"
      }.to change { ReminderLink.live.where(user_id: care_receiver.id).count }.from(0).to(1)
    end

    # One live link at a time. "Generate" leaving two outstanding is how a
    # caregiver ends up believing they revoked something they did not.
    it "replaces the previous one rather than leaving both live" do
      old = ReminderLink.mint(user: care_receiver)
      sign_in_caregiver

      post "/dashboard/senior/#{care_receiver.id}/reminder_link"

      expect(old.reload).to be_revoked
      expect(ReminderLink.live.where(user_id: care_receiver.id).count).to eq(1)
    end

    it "shows the address and whether the device has ever used it" do
      ReminderLink.mint(user: care_receiver)
      sign_in_caregiver

      get "/dashboard/senior/#{care_receiver.id}"

      expect(response.body).to include("Never used")
      expect(response.body).to include("/r/")
    end

    it "revokes one" do
      live = ReminderLink.mint(user: care_receiver)
      sign_in_caregiver

      post "/dashboard/senior/#{care_receiver.id}/reminder_link/#{live.id}/revoke"

      expect(live.reload).to be_revoked
      expect(flash[:notice]).to match(/stopped working/i)
    end

    # A stale page or a double-submitted form matches nothing. Confirming a
    # revocation this request did not perform is how somebody comes away
    # believing a device was cut off when it never was.
    it "does not claim to have revoked something it did not" do
      already = ReminderLink.mint(user: care_receiver)
      already.revoke!
      sign_in_caregiver

      post "/dashboard/senior/#{care_receiver.id}/reminder_link/#{already.id}/revoke"

      expect(flash[:notice]).to be_blank
      expect(flash[:alert]).to match(/already been stopped/i)
    end

    # And the mirror on creation: a first link replaced no bookmark, so saying
    # one stopped working is a small lie on the screen whose job is making the
    # state of a device legible.
    it "does not claim to have replaced a link that never existed" do
      sign_in_caregiver

      post "/dashboard/senior/#{care_receiver.id}/reminder_link"

      expect(flash[:notice]).to match(/New link ready/i)
      expect(flash[:notice]).not_to match(/old one/i)
    end

    it "says the old one stopped when there was one" do
      ReminderLink.mint(user: care_receiver)
      sign_in_caregiver

      post "/dashboard/senior/#{care_receiver.id}/reminder_link"

      expect(flash[:notice]).to match(/old one has stopped working/i)
    end

    context "a caregiver who may only look" do
      before { manage_link.update!(permission: :view) }

      it "is not offered the buttons" do
        ReminderLink.mint(user: care_receiver)
        sign_in_caregiver

        get "/dashboard/senior/#{care_receiver.id}"

        expect(response.body).not_to include("Create a device link")
        expect(response.body).not_to include("Stop this link")
      end

      # Hiding the buttons is not enough once a link can acknowledge. The
      # address *is* the write permission: copied into a browser it marks doses
      # done, which silences missed-dose mail and tells the other caregivers a
      # dose was taken — exactly what "can only look" is meant to withhold.
      it "is not shown the address itself" do
        live = ReminderLink.mint(user: care_receiver)
        sign_in_caregiver

        get "/dashboard/senior/#{care_receiver.id}"

        expect(response.body).not_to include(live.token)
      end

      # They still see whether the tablet is working, which is a fact about the
      # care rather than a key to it.
      it "still sees whether the device is alive" do
        ReminderLink.mint(user: care_receiver).record_use!
        sign_in_caregiver

        get "/dashboard/senior/#{care_receiver.id}"

        expect(response.body).to include("Last heard from")
      end

      # Hiding the button is not the gate. This is.
      it "cannot mint one with a hand-made request" do
        sign_in_caregiver

        expect {
          post "/dashboard/senior/#{care_receiver.id}/reminder_link"
        }.not_to change { ReminderLink.count }
      end

      it "cannot revoke one either" do
        live = ReminderLink.mint(user: care_receiver)
        sign_in_caregiver

        post "/dashboard/senior/#{care_receiver.id}/reminder_link/#{live.id}/revoke"

        expect(live.reload).not_to be_revoked
      end
    end

    # A caregiver with no link to this care receiver at all.
    it "cannot be minted by a stranger" do
      stranger = create(:user, :caregiver, name: "Nobody")
      post "/magic/verify", params: {
        token: stranger.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }

      expect {
        post "/dashboard/senior/#{care_receiver.id}/reminder_link"
      }.not_to change { ReminderLink.count }
    end
  end

  # A token in a log line is a credential in a log line. filter_parameters does
  # not reach path segments — it filters the query string and the parsed params —
  # so Rails' own "Started GET" line was writing the token verbatim.
  describe "what reaches the logs" do
    def filtered(path) = ActionDispatch::Request.new(Rack::MockRequest.env_for(path)).filtered_path

    it "redacts the token from the request path" do
      expect(filtered("/r/#{link.token}")).to eq("/r/[FILTERED]")
    end

    it "leaves every other path alone" do
      expect(filtered("/voice_reminders")).to eq("/voice_reminders")
      expect(filtered("/reminders/12/edit")).to eq("/reminders/12/edit")
    end

    # Anchored and stopping at the next separator, so it redacts the token and
    # not any path that merely starts the same way.
    it "does not swallow a longer path that begins the same way" do
      expect(filtered("/reports/2026")).to eq("/reports/2026")
    end
  end

  # Phase 2. Without this a device authorised by a bookmark could hear every
  # reminder and mark none of them done, so every dose would become a
  # missed-dose email and the caregiver would be told nothing was taken — which
  # is the product's central signal, inverted.
  describe "marking a dose done from a link" do
    def csrf_token = Nokogiri::HTML(response.body).at_css("meta[name='csrf-token']")&.[]("content")

    def occurrence_now(user: care_receiver, title: "Take your tablets")
      reminder_due(Time.current, title: title, user: user)
    end

    it "acknowledges" do
      occ = occurrence_now
      redeem

      post "/acknowledgements",
        params: { occurrence_id: occ.id, kind: "taken" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      expect(occ.reload.status).to eq("acknowledged")
    end

    it "snoozes" do
      occ = occurrence_now
      redeem

      post "/acknowledgements/snooze",
        params: { occurrence_id: occ.id, minutes: 10 }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }

      expect(response).to have_http_status(:created)
      expect(occ.reload.status).not_to eq("pending")
    end

    # The isolation that matters most, and it is enforced by the query each
    # action already ran: one credential, one care receiver.
    it "cannot acknowledge somebody else's reminder" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")
      theirs = occurrence_now(user: other, title: "Not mine")
      redeem

      expect {
        post "/acknowledgements",
          params: { occurrence_id: theirs.id, kind: "taken" }.to_json,
          headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => csrf_token }
      }.not_to change { theirs.reload.status }
    end

    it "stops working the moment the link is revoked" do
      occ = occurrence_now
      redeem
      token = csrf_token
      link.revoke!

      post "/acknowledgements",
        params: { occurrence_id: occ.id, kind: "taken" }.to_json,
        headers: { "CONTENT_TYPE" => "application/json", "X-CSRF-Token" => token }

      expect(occ.reload.status).to eq("pending")
    end

    # Forgery protection is untouched: a link-mode page is issued a session
    # cookie and renders csrf_meta_tags like any other, so the existing check
    # applies rather than being skipped for this credential.
    #
    # Turned on for this example only. The test environment disables it, which
    # would have made the assertion pass while proving nothing — the request
    # would have succeeded with no token because no token was ever required.
    it "still refuses a request with no CSRF token" do
      occ = occurrence_now
      redeem

      begin
        ActionController::Base.allow_forgery_protection = true

        post "/acknowledgements",
          params: { occurrence_id: occ.id, kind: "taken" }.to_json,
          headers: { "CONTENT_TYPE" => "application/json" }

        # Rails turns the forgery failure into a 422 here rather than raising,
        # because the test environment rescues it the way production does.
        expect(response).to have_http_status(:unprocessable_entity)
      ensure
        ActionController::Base.allow_forgery_protection = false
      end

      expect(occ.reload.status).to eq("pending")
    end
  end

  # A cookie set once for a year and never renewed would expire under a tablet
  # in daily use, on the anniversary of the day it was set up — the very failure
  # this feature exists to end, arriving twelve months later instead of one.
  describe "keeping an active device authorised" do
    it "renews the cookie when it records the device as alive" do
      redeem

      travel(11.months) do
        get "/voice_reminders/today"

        expect(response.headers["Set-Cookie"].to_s).to include("reminder_link")
      end
    end

    # On the same throttle as the timestamp: a device polling every few seconds
    # writes one cookie every ten minutes, not one per request.
    it "does not rewrite it on every poll" do
      redeem

      get "/voice_reminders/today"

      expect(response.headers["Set-Cookie"].to_s).not_to include("reminder_link")
    end
  end

  describe "minting" do
    it "gives each link its own token" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")

      expect(ReminderLink.mint(user: care_receiver).token)
        .not_to eq(ReminderLink.mint(user: other).token)
    end

    # The index refusing a racing caregiver is correct; a 500 in their browser
    # is not. Whichever link now exists is real, so the honest answer is to say
    # somebody else got there first rather than to retry and revoke what they
    # are at that moment reading off their screen.
    it "tells a caregiver who lost the race, rather than failing" do
      CaregiverLink.create!(senior: care_receiver, caregiver: caregiver, permission: :manage)
      post "/magic/verify", params: {
        token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes)
      }
      allow(ReminderLink).to receive(:mint).and_raise(ActiveRecord::RecordNotUnique.new("duplicate"))

      post "/dashboard/senior/#{care_receiver.id}/reminder_link"

      expect(response).to redirect_to(senior_dashboard_path(care_receiver))
      expect(flash[:alert]).to match(/somebody else created a link/i)
    end

    # The database, not the controller's good intentions. Two caregivers
    # pressing "Create a device link" at the same moment would otherwise each
    # revoke what they saw and mint what they wanted, leaving a live credential
    # the panel does not show and nobody thinks to revoke.
    it "refuses a second live link for the same person" do
      ReminderLink.mint(user: care_receiver)

      expect { ReminderLink.mint(user: care_receiver) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new one once the old is revoked" do
      ReminderLink.mint(user: care_receiver).revoke!

      expect { ReminderLink.mint(user: care_receiver) }.not_to raise_error
    end

    it "keeps a revoked link, so its last use is still readable" do
      link.record_use!
      link.revoke!

      expect(ReminderLink.exists?(link.id)).to be(true)
      expect(link.reload.last_used_at).to be_present
    end
  end
end
