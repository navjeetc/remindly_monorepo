# frozen_string_literal: true

require "rails_helper"

# The page a care receiver's device leaves open all day. It moved out of
# DashboardController so that a second kind of credential — a reminder link —
# can be honoured here and nowhere else, and it had no coverage of its own when
# it moved: the suite exercised the acknowledgement endpoints it calls and never
# the page itself.
#
# These pin what it did before the move, so the link work that follows is built
# on something that is known rather than assumed.
RSpec.describe "The voice reminders page", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:care_receiver) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def reminder_due(at, title: "Take your tablets", user: care_receiver)
    reminder = Reminder.create!(user: user, title: title, rrule: "FREQ=DAILY", tz: user.tz)
    Occurrence.create!(reminder: reminder, scheduled_at: at, status: :pending)
  end

  describe "the page" do
    it "is served to the care receiver it belongs to" do
      sign_in(care_receiver)

      get "/voice_reminders"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Reminders")
    end

    # A caregiver here has made a navigation mistake, not an authorisation
    # attempt: the reminders belong to the person being cared for, so there is
    # nothing on this page for them to hear.
    it "sends a caregiver back to their own dashboard" do
      sign_in(caregiver)

      get "/voice_reminders"

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to match(/care receivers/i)
    end

    it "sends a stranger to sign in" do
      get "/voice_reminders"

      expect(response).to redirect_to(login_path)
    end
  end

  # The script is served from public/ and versioned in the query string. That
  # version used to be Time.now.to_i, which changes every second — so the tablet
  # re-downloaded it on every load and every reload, on the device this page is
  # deliberately light for.
  describe "the script tag" do
    it "carries the same version on two loads of the same page" do
      sign_in(care_receiver)

      get "/voice_reminders"
      first = response.body[/voice_reminders\.js\?v=(\d+)/, 1]
      get "/voice_reminders"
      second = response.body[/voice_reminders\.js\?v=(\d+)/, 1]

      expect(first).to be_present
      expect(second).to eq(first)
    end

    it "versions on the file rather than the clock" do
      sign_in(care_receiver)

      get "/voice_reminders"

      expect(response.body).to include("voice_reminders.js?v=#{VoiceRemindersController.script_version}")
      expect(VoiceRemindersController.script_version)
        .to eq(File.mtime(Rails.public_path.join("voice_reminders.js")).to_i)
    end
  end

  # A request that straddles midnight must not read its start from one day and
  # its end from the next: that is a forty-eight hour window on the endpoint
  # deciding what a care receiver is told to do today.
  describe "the day the JSON is read for" do
    it "reads the clock once" do
      zone = ActiveSupport::TimeZone["America/New_York"]
      allow(ActiveSupport::TimeZone).to receive(:[]).and_call_original
      allow(ActiveSupport::TimeZone).to receive(:[]).with("America/New_York").and_return(zone)
      allow(zone).to receive(:now).and_call_original
      sign_in(care_receiver)

      get "/voice_reminders/today"

      expect(zone).to have_received(:now).once
    end
  end

  describe "the JSON the device polls" do
    it "returns today's pending reminders in the care receiver's own timezone" do
      tz = ActiveSupport::TimeZone["America/New_York"]
      travel_to(tz.parse("2026-09-04 09:00")) do
        due = reminder_due(tz.parse("2026-09-04 20:00"))
        sign_in(care_receiver)

        get "/voice_reminders/today"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.map { |o| o["id"] }).to eq([ due.id ])
        expect(response.parsed_body.first["title"]).to eq("Take your tablets")
      end
    end

    # The zone matters here rather than being decoration: an 8pm dose in New
    # York is tomorrow in UTC, and reading the server's clock would drop it.
    it "does not return a reminder that belongs to a different day" do
      tz = ActiveSupport::TimeZone["America/New_York"]
      travel_to(tz.parse("2026-09-04 09:00")) do
        reminder_due(tz.parse("2026-09-05 09:00"))
        sign_in(care_receiver)

        get "/voice_reminders/today"

        expect(response.parsed_body).to be_empty
      end
    end

    it "never returns somebody else's reminders" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")
      tz = ActiveSupport::TimeZone["America/New_York"]
      travel_to(tz.parse("2026-09-04 09:00")) do
        mine = reminder_due(tz.parse("2026-09-04 10:00"))
        reminder_due(tz.parse("2026-09-04 11:00"), title: "Not mine", user: other)
        sign_in(care_receiver)

        get "/voice_reminders/today"

        expect(response.parsed_body.map { |o| o["id"] }).to eq([ mine.id ])
      end
    end

    it "refuses a caregiver" do
      sign_in(caregiver)

      get "/voice_reminders/today"

      expect(response).to have_http_status(:unauthorized)
    end

    # A status rather than a redirect, because this endpoint is only ever read
    # by fetch(), which follows redirects and would hand the page a 200 full of
    # login HTML.
    it "refuses a stranger" do
      get "/voice_reminders/today"

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
