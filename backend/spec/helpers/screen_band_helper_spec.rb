# frozen_string_literal: true

require "rails_helper"

# Which name the screen band shows (#176), and whose. The request specs in
# distinct_dashboards_spec cover the pages; these cover the cases a page is
# awkward to reach for.
RSpec.describe ApplicationHelper, type: :helper do
  describe "#band_name" do
    it "prefers a nickname, as display_name does" do
      expect(helper.band_name(build(:user, name: "Margaret", nickname: "Mum"))).to eq("Mum")
    end

    it "uses the name when there is no nickname" do
      expect(helper.band_name(build(:user, name: "Margaret", nickname: nil))).to eq("Margaret")
    end

    # display_name would give the address, and then "Someone"; the band would
    # rather name nobody than print either.
    it "names nobody when there is only an email address, or nothing at all" do
      expect(helper.band_name(build(:user, name: nil, nickname: nil, email: "mom@example.com"))).to be_nil
      expect(helper.band_name(build(:user, name: nil, nickname: nil, email: nil))).to be_nil
    end

    it "names nobody for no user" do
      expect(helper.band_name(nil)).to be_nil
    end
  end

  describe "#band_care_receiver" do
    let(:caregiver) { create(:user, :caregiver, name: "Jane") }
    let(:senior) { create(:user, :senior, name: "Mom") }

    # current_user is a controller helper_method, so the bare view a helper
    # spec renders against does not have one to stub.
    before do
      signed_in = caregiver
      helper.define_singleton_method(:current_user) { signed_in }
    end

    it "is the senior the page is about" do
      assign(:senior, senior)

      expect(helper.band_care_receiver).to eq(senior)
    end

    # SchedulingIntegrationsController#show, #edit and #sync set only this.
    it "falls back to the senior of the integration the page is about" do
      assign(:integration, SchedulingIntegration.new(senior: senior))

      expect(helper.band_care_receiver).to eq(senior)
    end

    it "is nobody on the form that sets someone new up" do
      assign(:senior, User.new(name: "Not yet"))

      expect(helper.band_care_receiver).to be_nil
    end
  end
end
