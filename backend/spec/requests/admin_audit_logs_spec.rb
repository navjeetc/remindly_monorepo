require "rails_helper"

# The summary tiles used to query Ahoy::Event directly, so they showed all-time
# totals next to a filtered event list. Applying any filter produced three
# numbers that did not reconcile: "Total Events" narrowed, the login counts
# did not.
RSpec.describe "Admin audit log filters (admin/audit_logs#index)", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def track(name, user:, time:)
    visit = Ahoy::Visit.create!(user: user, started_at: time)
    Ahoy::Event.create!(name: name, user: user, visit: visit, time: time)
  end

  let(:admin)     { create(:user, :admin, email: "admin@example.com") }
  let(:caregiver) { create(:user, :caregiver, email: "cg@example.com") }

  before do
    track "Login Success", user: admin,     time: 1.day.ago
    track "Login Success", user: caregiver, time: 1.day.ago
    track "Login Failed",  user: caregiver, time: 1.day.ago
    track "Login Success", user: caregiver, time: 200.days.ago
    track "Login Failed",  user: caregiver, time: 200.days.ago

    sign_in(admin)
  end

  # The tiles render as "<count></dd>" under their own coloured block, so read
  # each one out of its labelled card rather than scanning the whole page.
  def tile(label)
    section = response.body[/#{Regexp.escape(label)}<\/dt>.*?<\/dd>/m]
    section[/<dd[^>]*>\s*(\d+)\s*<\/dd>/m, 1]&.to_i
  end

  it "counts every event when no filter is applied" do
    get "/admin/audit_logs"

    expect(tile("Total Events")).to eq(5)
    expect(tile("Successful Logins")).to eq(3)
    expect(tile("Failed Logins")).to eq(2)
  end

  it "narrows the login tiles to the selected user" do
    get "/admin/audit_logs", params: { user_id: admin.id }

    expect(tile("Total Events")).to eq(1)
    expect(tile("Successful Logins")).to eq(1)
    expect(tile("Failed Logins")).to eq(0)
  end

  it "narrows the login tiles to the selected date range" do
    get "/admin/audit_logs", params: { date_from: 7.days.ago.to_date.to_s }

    expect(tile("Total Events")).to eq(3)
    expect(tile("Successful Logins")).to eq(2)
    expect(tile("Failed Logins")).to eq(1)
  end

  # Filtering to one event type zeroes the other tile — the tiles describe the
  # listed rows, and there are no failed logins among them.
  it "zeroes the tile for an event type the filter excludes" do
    get "/admin/audit_logs", params: { event_filter: "Login Success" }

    expect(tile("Total Events")).to eq(3)
    expect(tile("Successful Logins")).to eq(3)
    expect(tile("Failed Logins")).to eq(0)
  end

  # Date.parse raises on anything it cannot read, so a hand-edited query string
  # used to 500 the page.
  it "ignores an unparseable date filter instead of erroring" do
    get "/admin/audit_logs", params: { date_from: "not-a-date" }

    expect(response).to have_http_status(:ok)
    expect(tile("Total Events")).to eq(5)
  end

  it "still applies the other filters when one date is unparseable" do
    get "/admin/audit_logs", params: { date_from: "garbage", user_id: admin.id }

    expect(response).to have_http_status(:ok)
    expect(tile("Total Events")).to eq(1)
    expect(tile("Successful Logins")).to eq(1)
  end

  it "keeps a valid date bound when the other one is unparseable" do
    get "/admin/audit_logs", params: { date_from: 7.days.ago.to_date.to_s, date_to: "13/13/2026" }

    expect(response).to have_http_status(:ok)
    expect(tile("Total Events")).to eq(3)
  end

  it "keeps the tiles consistent with the paginated list total" do
    get "/admin/audit_logs", params: { user_id: caregiver.id }

    expect(tile("Total Events")).to eq(4)
    expect(response.body).to include("Recent Events (4)")
  end
end
