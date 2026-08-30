# frozen_string_literal: true

require "rails_helper"

# The bug this guards against did not raise, log, or fail a request. A caregiver
# opened her profile, changed her name, pressed Save, and was moved to UTC-12 —
# seventeen hours off Eastern — because the select's option values were Rails
# zone names while her column held the IANA default, so nothing was preselected
# and the browser submitted the first option in the list. Everything downstream
# kept working, on the wrong day.
#
# So these are round-trip tests: what the form offers has to be what the column
# holds, and saving without touching the zone has to leave the zone alone.
RSpec.describe "Profile timezone", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)

  def zone_select = doc.at_css("select[name='user[tz]']")

  let(:user) { create(:user, :caregiver, name: "Christy", tz: "America/New_York") }

  it "preselects the user's stored zone" do
    sign_in(user)
    get "/profile"

    expect(zone_select.at_css("option[selected]")[:value]).to eq("America/New_York")
  end

  it "does not offer the Rails zone name as a value, which nothing stores" do
    sign_in(user)
    get "/profile"

    values = zone_select.css("option").map { |option| option[:value] }

    expect(values).to include("America/New_York")
    expect(values).not_to include("Eastern Time (US & Canada)")
  end

  it "leaves the zone untouched when the form is submitted unchanged" do
    sign_in(user)
    get "/profile"

    expect {
      patch "/profile", params: { user: { name: "Christy O'Connor", tz: "America/New_York" } }
    }.not_to change { user.reload.tz }
  end

  it "still accepts a Rails zone name, storing it as the identifier" do
    sign_in(user)

    patch "/profile", params: { user: { name: "Christy", tz: "Eastern Time (US & Canada)" } }

    expect(user.reload.tz).to eq("America/New_York")
  end
end
