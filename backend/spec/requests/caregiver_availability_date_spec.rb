# frozen_string_literal: true

require "rails_helper"

# Clicking a day on the availability calendar opens the form with
# ?date=YYYY-MM-DD. The form ignored it and always showed today, so choosing
# the 26th and pressing save quietly added availability for the 24th.
RSpec.describe "Adding availability for the day picked on the calendar", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 9, 24).in_time_zone.change(hour: 10)) { example.run } }

  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def date_field_value
    Nokogiri::HTML(response.body).at_css("input[type=date][name='caregiver_availability[date]']")&.[]("value")
  end

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:native_scheduling).and_return(true)
    sign_in(caregiver)
  end

  it "opens on the day that was clicked" do
    get "/caregiver_availabilities/new", params: { date: "2026-09-26" }

    expect(date_field_value).to eq("2026-09-26")
  end

  it "opens on today when no day was given" do
    get "/caregiver_availabilities/new"

    expect(date_field_value).to eq("2026-09-24")
  end

  # A past cell is still clickable; the form does not accept a past date, so it
  # opens on the first day it will.
  it "opens on today for a day that has already passed" do
    get "/caregiver_availabilities/new", params: { date: "2026-09-20" }

    expect(date_field_value).to eq("2026-09-24")
  end

  it "ignores a date it cannot read" do
    get "/caregiver_availabilities/new", params: { date: "not-a-date" }

    expect(response).to have_http_status(:ok)
    expect(date_field_value).to eq("2026-09-24")
  end

  # The same hardcoded value also threw away the date somebody had just entered
  # whenever a save failed and the form came back.
  it "keeps the entered date when a save is refused" do
    post "/caregiver_availabilities", params: {
      caregiver_availability: { date: "2026-09-27", start_time: "17:00", end_time: "09:00" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(date_field_value).to eq("2026-09-27")
  end
end
