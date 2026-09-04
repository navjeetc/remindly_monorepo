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
    it "lands on the voice page" do
      redeem

      expect(response).to redirect_to(voice_reminders_path)
    end

    # The point of the exchange. After the redirect the token is out of the
    # address bar, so it stops appearing in history, in referrers, and to
    # anybody reading the screen — while the bookmark still holds it, which is
    # what makes the setup survive cookie loss.
    it "leaves the token out of the page it lands on" do
      redeem
      follow_redirect!

      expect(response.body).not_to include(link.token)
    end

    it "opens the voice page without signing in" do
      redeem
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Reminders")
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

    it "stops the polling too" do
      redeem
      link.revoke!

      get "/voice_reminders/today"

      expect(response).to redirect_to(login_path)
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
      "tasks" => "/tasks",
      "the pairing screen" => "/dashboard/pair",
      "a pairing token" => "/dashboard/generate",
      "the caregiver list" => "/caregiver_links",
      "their own reminders as data" => "/reminders",
      "the reminder form" => "/reminders/new"
    }.each do |name, path|
      it "cannot reach #{name}" do
        get path

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

    before do
      redeem
      follow_redirect!
    end

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

  describe "minting" do
    it "gives each link its own token" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")

      expect(ReminderLink.mint(user: care_receiver).token)
        .not_to eq(ReminderLink.mint(user: other).token)
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
