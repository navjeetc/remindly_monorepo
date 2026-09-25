# frozen_string_literal: true

require "rails_helper"

# #174: calling hours were one window for everybody, 8am-9pm, and a caregiver
# setting up her mother at 6am was refused twice. The window is now each care
# receiver's own, moved by a caregiver who may manage them.
RSpec.describe "Calling hours", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def set_hours(start_hour, end_hour)
    patch "/dashboard/senior/#{senior.id}/calling_hours",
      params: { user: { calling_hours_start: start_hour, calling_hours_end: end_hour } }
  end

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
    sign_in(caregiver)
  end

  it "is moved by a caregiver who manages the care receiver" do
    set_hours(6, 22)

    expect(senior.reload.calling_hours).to eq(6...22)
    expect(response).to redirect_to("/dashboard/senior/#{senior.id}")
    expect(flash[:notice]).to eq("We'll call Mom between 6am and 10pm their time.")
  end

  # The select offers only allowed hours; a hand-made request is refused by the
  # model rather than trusted.
  it "refuses a window that reaches into the small hours" do
    set_hours(3, 21)

    expect(senior.reload.calling_hours).to eq(8...21)
    expect(flash[:alert]).to be_present
  end

  it "refuses a window that closes before it opens" do
    set_hours(20, 9)

    expect(senior.reload.calling_hours).to eq(8...21)
    expect(flash[:alert]).to include("later than the earliest")
  end

  it "is not the view-only caregiver's to change" do
    link.update!(permission: :view)

    set_hours(6, 22)

    expect(response).to have_http_status(:forbidden)
    expect(senior.reload.calling_hours).to eq(8...21)
  end

  it "cannot be changed for somebody the caregiver is not linked to" do
    stranger = create(:user, :senior, name: "Stranger")

    patch "/dashboard/senior/#{stranger.id}/calling_hours",
      params: { user: { calling_hours_start: 6, calling_hours_end: 22 } }

    expect(response).to have_http_status(:not_found)
    expect(stranger.reload.calling_hours).to eq(8...21)
  end

  it "is closed while phone reminders are switched off" do
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)

    set_hours(6, 22)

    expect(response).to have_http_status(:forbidden)
  end

  # The case that prompted all of this: at 6:15am, before the care receiver has
  # agreed to anything, the consent call is offered once the window says so.
  describe "on the phone panel" do
    before { senior.update!(phone: "+14132129092") }

    def panel = Nokogiri::HTML(response.body)

    it "shows the window as it stands" do
      senior.update!(calling_hours_start: 7, calling_hours_end: 20)

      get "/dashboard/senior/#{senior.id}"

      expect(panel.at_css("#user_calling_hours_start option[selected]")["value"]).to eq("7")
      expect(panel.at_css("#user_calling_hours_end option[selected]")["value"]).to eq("20")
    end

    it "offers the consent call at 6:15am once the window opens at 6" do
      travel_to ActiveSupport::TimeZone["America/New_York"].local(2026, 9, 25, 6, 15) do
        get "/dashboard/senior/#{senior.id}"
        expect(panel.at_css("form[action$='/verify_phone'] button")["disabled"]).to be_present

        set_hours(6, 21)
        get "/dashboard/senior/#{senior.id}"
        expect(panel.at_css("form[action$='/verify_phone'] button")["disabled"]).to be_nil
      end
    end

    it "says the care receiver's own hours when it will not ring yet" do
      senior.update!(calling_hours_start: 10, calling_hours_end: 18)

      travel_to ActiveSupport::TimeZone["America/New_York"].local(2026, 9, 25, 9, 0) do
        get "/dashboard/senior/#{senior.id}"
      end

      expect(panel.text.squish).to include("We only call between 10am and 6pm, so this won't ring yet.")
    end
  end
end
