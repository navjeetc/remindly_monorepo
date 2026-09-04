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

    it "refuses a stranger" do
      get "/voice_reminders/today"

      expect(response).to redirect_to(login_path)
    end
  end
end
