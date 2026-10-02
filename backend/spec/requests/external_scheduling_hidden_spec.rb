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

  # Review caught that nothing exercised the badge: with no synced task in the
  # list, removing its flag check left this spec green.
  describe "the provider badge on a synced task" do
    before do
      senior.tasks_as_senior.create!(
        title: "Dentist (synced)", task_type: "appointment", created_by: caregiver,
        external_source: "acuity", scheduled_at: 2.days.from_now
      )
    end

    def badge
      Nokogiri::HTML(response.body).css("span").find { |span| span.text.include?("🔗") }
    end

    it "is hidden while the flag is off" do
      get "/seniors/#{senior.id}/tasks"

      expect(response.body).to include("Dentist (synced)")
      expect(badge).to be_nil
    end

    it "shows again when the flag is on" do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:external_scheduling).and_return(true)

      get "/seniors/#{senior.id}/tasks"

      expect(badge&.text).to include("Acuity")
    end
  end

  it "is not described in the privacy policy" do
    get "/privacy"
    text = Nokogiri::HTML(response.body).text

    expect(text).not_to match(/acuity|connected calendar|linked calendar/i)
  end
end
