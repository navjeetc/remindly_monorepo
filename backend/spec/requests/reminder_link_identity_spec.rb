# frozen_string_literal: true

require "rails_helper"

# Found in production: two incognito windows, each opened on a different care
# receiver's link, and one of them showing the other person's appointments under
# its own address.
#
# Windows in one browser share a single cookie jar, incognito ones included, and
# the reminder-link cookie holds whichever link was opened last. The device page
# is identified by its address, but its data came from that one cookie -- so
# every open window showed the most recently opened person. The page now sends
# its own link with each request, and that wins.
#
# A request spec's cookie jar is exactly that shared jar: every `get` here comes
# from the same browser, whatever window it stands for.
RSpec.describe "Which person a reminder link shows", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:first)  { create(:user, :senior, name: "First", email: "first@example.com") }
  let(:second) { create(:user, :senior, name: "Second", email: "second@example.com") }
  let(:first_link)  { ReminderLink.mint(user: first) }
  let(:second_link) { ReminderLink.mint(user: second) }

  before do
    [ first, second ].each do |senior|
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active)
      Task.create!(senior: senior, created_by: caregiver, title: "#{senior.name}'s appointment",
                   scheduled_at: 1.hour.from_now, visible_to_senior: true)
    end
  end

  def coming_up(as: nil)
    headers = as ? { "X-Reminder-Link" => as.token } : {}
    get "/voice_reminders/coming_up", headers: headers
    JSON.parse(response.body).map { |t| t["title"] }
  end

  describe "two windows, one browser" do
    before do
      get "/r/#{first_link.token}"   # window one opens First's link
      get "/r/#{second_link.token}"  # window two opens Second's -- the cookie now says Second
    end

    # The bug as reported: window one, still on First's address, refreshing.
    it "keeps showing the first window's own person" do
      expect(coming_up(as: first_link)).to eq([ "First's appointment" ])
    end

    it "shows the second window its own person" do
      expect(coming_up(as: second_link)).to eq([ "Second's appointment" ])
    end

    # The header is one window speaking for its own page. Letting it rewrite the
    # shared cookie would have the windows overwriting each other.
    it "does not let one window's request change the other's credential" do
      travel 11.minutes do
        coming_up(as: first_link)
        expect(coming_up).to eq([ "Second's appointment" ])
      end
    end
  end

  # The page's buttons are plain forms, and they relied on the shared cookie too.
  # "No" on a provisional account deletes it, so window one's No answering for
  # window two's person destroyed the wrong account.
  describe "the buttons on a provisional person's page" do
    before do
      [ first, second ].each { |s| s.senior_links.update_all(state: CaregiverLink.states[:provisional]) }
      get "/r/#{first_link.token}"   # window one: First's consent question
      get "/r/#{second_link.token}"  # window two: Second's -- the cookie now says Second
    end

    # A field for the page to fill from its own address -- empty in the HTML,
    # because the token is never printed into the page.
    it "gives each button a field for the page's own link, without printing the token" do
      get "/r/#{first_link.token}"

      field = Nokogiri::HTML(response.body)
                      .at_css("form[action='/voice_reminders/decline'] input[name='reminder_link_token']")
      expect(field).to be_present
      expect(response.body).not_to include(first_link.token)
    end

    # Without JavaScript the field stays empty and a post would answer with the
    # shared cookie. Rendered disabled, the buttons do nothing instead.
    it "renders the buttons disabled until the page has filled in its link" do
      get "/r/#{first_link.token}"

      buttons = Nokogiri::HTML(response.body).css("button[data-needs-reminder-link='true']")
      expect(buttons.size).to eq(2)
      expect(buttons.map { |b| b["disabled"] }).to all(be_present)
    end

    it "answers No for the window's own person, never the other one" do
      post "/voice_reminders/decline", params: { reminder_link_token: first_link.token }

      expect(User.exists?(first.id)).to be(false)
      expect(User.exists?(second.id)).to be(true)
    end

    # Yes starts somebody's reminders and tells their caregiver it is running,
    # so it must be the window's own person who agreed.
    it "answers Yes for the window's own person, never the other one" do
      post "/voice_reminders/start", params: { reminder_link_token: first_link.token }

      expect(first.senior_links.pluck(:state)).to all(eq("active"))
      expect(second.senior_links.pluck(:state)).to all(eq("provisional"))
    end
  end

  # Stop revokes a device's link. Pressed in one window, it must end that
  # window's link and leave the other person's device working.
  describe "the Stop button" do
    before do
      get "/r/#{first_link.token}"   # window one
      get "/r/#{second_link.token}"  # window two -- the cookie now says Second
    end

    it "revokes the window's own link, not the other one" do
      post "/voice_reminders/stop", params: { reminder_link_token: first_link.token }

      expect(first_link.reload.revoked_at).to be_present
      expect(second_link.reload.revoked_at).to be_nil
    end

    it "leaves the other window's page working" do
      post "/voice_reminders/stop", params: { reminder_link_token: first_link.token }

      expect(coming_up(as: second_link)).to eq([ "Second's appointment" ])
    end
  end

  # A page that asked for one person is never answered with whoever the cookie
  # happens to hold.
  it "does not fall back to the cookie when the page's own link has been revoked" do
    get "/r/#{second_link.token}"
    first_link.update!(revoked_at: Time.current)

    get "/voice_reminders/coming_up", headers: { "X-Reminder-Link" => first_link.token }

    expect(response).to have_http_status(:unauthorized)
  end

  describe "a browser that is also signed in" do
    before { post "/magic/verify", params: { token: first.signed_id(purpose: :magic_login, expires_in: 30.minutes) } }

    # The address names Second; the session is First's. The link is the
    # deliberate credential and the session is ambient.
    it "shows the link's person rather than the signed-in one" do
      get "/r/#{second_link.token}"

      expect(coming_up(as: second_link)).to eq([ "Second's appointment" ])
    end

    # The revoked-link rule has to hold in a signed-in browser too. Falling back
    # to the session would show -- and let Done act for -- the signed-in person
    # under the revoked link's address.
    it "refuses a revoked link rather than answering as the signed-in person" do
      get "/r/#{second_link.token}"
      second_link.update!(revoked_at: Time.current)

      get "/voice_reminders/coming_up", headers: { "X-Reminder-Link" => second_link.token }

      expect(response).to have_http_status(:unauthorized)
    end

    # The write side. The page shows the link's person, so Done and Snooze must
    # act for that person too -- a regression here would show Second while
    # marking First's dose taken.
    describe "Done and Snooze" do
      def occurrence_for(senior)
        reminder = Reminder.create!(user: senior, title: "#{senior.name}'s tablet", category: :medication,
                                    rrule: "FREQ=DAILY", tz: senior.tz)
        Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending)
      end

      let!(:firsts)  { occurrence_for(first) }
      let!(:seconds) { occurrence_for(second) }
      let(:as_second) { { "X-Reminder-Link" => second_link.token } }

      it "marks the link's person's dose taken, not the signed-in person's" do
        post "/acknowledgements", params: { occurrence_id: seconds.id, kind: "taken" }, headers: as_second

        expect(response).to have_http_status(:created)
        expect(seconds.reload.status).to eq("acknowledged")
        expect(firsts.reload.status).to eq("pending")
      end

      # One credential, one person: the link cannot reach the session's reminders.
      it "cannot mark the signed-in person's dose from the other person's page" do
        post "/acknowledgements", params: { occurrence_id: firsts.id, kind: "taken" }, headers: as_second

        expect(firsts.reload.status).to eq("pending")
      end

      it "snoozes the link's person's reminder, not the signed-in person's" do
        post "/acknowledgements/snooze", params: { occurrence_id: seconds.id }, headers: as_second

        expect(response).to have_http_status(:created)
        expect(Acknowledgement.where(occurrence_id: seconds.id, kind: "snooze")).to exist
        expect(Acknowledgement.where(occurrence_id: firsts.id)).not_to exist
      end
    end

    # Only a link this request names outranks a session. A cookie left over from
    # opening somebody's link earlier must not take over the signed-in person's
    # own page.
    it "does not let a leftover link cookie outrank the session" do
      get "/r/#{second_link.token}"  # sets the browser-wide cookie to Second

      expect(coming_up).to eq([ "First's appointment" ])
    end

    it "still shows the signed-in person where no link is involved" do
      expect(coming_up).to eq([ "First's appointment" ])
    end

    # A provisional account's first visit is its consent question. The session
    # used to answer instead, so the question never appeared.
    it "asks a provisional person their consent question, not the signed-in person's day" do
      second.senior_links.update_all(state: CaregiverLink.states[:provisional])

      get "/r/#{second_link.token}"

      expect(response.body).to include("Jane")
      expect(response.body).not_to include("First's appointment")
    end
  end
end
