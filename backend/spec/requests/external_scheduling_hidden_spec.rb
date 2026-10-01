# frozen_string_literal: true

require "rails_helper"

# Connecting an external calendar (Acuity) is not offered: it sits behind the
# external_scheduling flag, which is off, and production has never held an
# integration or a synced task. Nothing a caregiver sees, and nothing the
# privacy policy promises, should describe it while that is so.
RSpec.describe "External scheduling, while it is switched off", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  it "offers no Acuity or Calendly filter on the task list" do
    get "/seniors/#{senior.id}/tasks"
    page = Nokogiri::HTML(response.body)

    expect(page.at_css("select[name='external_source']")).to be_nil
    expect(page.text).not_to include("Calendly")
  end

  it "shows the filter again when the flag is on" do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:external_scheduling).and_return(true)

    get "/seniors/#{senior.id}/tasks"

    expect(Nokogiri::HTML(response.body).at_css("select[name='external_source']")).to be_present
  end

  it "is not described in the privacy policy" do
    get "/privacy"
    text = Nokogiri::HTML(response.body).text

    expect(text).not_to match(/acuity|connected calendar|linked calendar/i)
  end
end
