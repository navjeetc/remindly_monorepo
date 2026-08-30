# frozen_string_literal: true

require "rails_helper"

# The screens were reachable from the day they were written because the
# external_scheduling flag was declared alongside them and then never checked.
# Nothing syncs on a schedule, so an integration only pulls appointments when
# somebody presses Sync by hand — which is not what "connect your calendar"
# offers. These specs hold the flag shut and, more importantly, hold the door
# shut rather than only the link.
RSpec.describe "Scheduling integrations while the feature is off", type: :request do
  let(:caregiver) { create(:user, :caregiver, email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  before { sign_in(caregiver) }

  it "is off by default" do
    expect(FeatureFlag.enabled?(:external_scheduling)).to be(false)
  end

  it "offers no link into it from the senior's page" do
    get "/dashboard/senior/#{senior.id}"

    expect(response.body).not_to include("Scheduling Integrations")
  end

  # The part that matters: a hidden link is not a closed door.
  it "turns away someone holding the URL" do
    get "/seniors/#{senior.id}/scheduling_integrations"

    expect(response).to redirect_to(dashboard_path)
  end

  it "turns away the new-integration form too" do
    get "/seniors/#{senior.id}/scheduling_integrations/new"

    expect(response).to redirect_to(dashboard_path)
  end

  it "refuses to create one" do
    expect {
      post "/seniors/#{senior.id}/scheduling_integrations", params: {
        scheduling_integration: { provider: "acuity", api_key: "x" }
      }
    }.not_to change(SchedulingIntegration, :count)
  end

  context "when it is switched back on" do
    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:external_scheduling).and_return(true)
    end

    it "lets a caregiver back in, so this is a flag and not a removal" do
      get "/seniors/#{senior.id}/scheduling_integrations"

      expect(response).to have_http_status(:ok)
    end
  end
end
