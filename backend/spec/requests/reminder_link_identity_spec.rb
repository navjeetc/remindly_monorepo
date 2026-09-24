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
