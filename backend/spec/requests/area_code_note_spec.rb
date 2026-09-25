# frozen_string_literal: true

require "rails_helper"

# #173: a caregiver saved 414 for 413 and three consent calls rang a stranger
# in Wisconsin. The panel now says where a saved number's area code is, as
# information beside the number rather than a warning about it.
RSpec.describe "The area code beside a care receiver's number", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def text = Nokogiri::HTML(response.body).text.squish

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
    sign_in(caregiver)
  end

  it "names the state of the saved number's area code" do
    senior.update!(phone: "+14142129092")

    get "/dashboard/senior/#{senior.id}"

    expect(text).to include("Area code 414 · Wisconsin")
  end

  it "follows the number when it is corrected" do
    senior.update!(phone: "+14142129092")
    patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "413-212-9092" } }

    get "/dashboard/senior/#{senior.id}"

    expect(text).to include("Area code 413 · Massachusetts")
    expect(text).not_to include("Wisconsin")
  end

  it "says nothing before a number is saved" do
    get "/dashboard/senior/#{senior.id}"

    expect(text).not_to include("Area code")
  end

  it "says nothing for a number outside +1, rather than guessing" do
    senior.update!(phone: "+442071234567")

    get "/dashboard/senior/#{senior.id}"

    expect(text).not_to include("Area code")
  end
end
