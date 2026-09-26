# frozen_string_literal: true

require "rails_helper"

# #176: a caregiver could not tell her own page about her mother from her
# mother's screen. Her mother is named "Me", so the caregiver page was headed
# "Me" and the device screen "My Reminders" -- two screens reading as "mine",
# in the same colours. Each screen now says whose it is in words, and the care
# receiver's screens have their own background to back that up.
RSpec.describe "Whose screen this is", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Christy") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)
  def warm? = response.body.include?(ApplicationHelper::CARE_RECEIVER_BACKGROUND)

  describe "the caregiver's screens" do
    before { sign_in(caregiver) }

    it "labels the caregiver's home as the caregiver view" do
      get "/dashboard"

      expect(doc.text.squish).to include("Caregiver view")
      expect(doc.text).not_to include("own screen")
      expect(warm?).to be(false)
    end

    # The case itself: a care receiver named "Me" no longer heads the page
    # alone, where it reads as the caregiver's own.
    it "says who is being cared for above their name" do
      senior.update!(name: "Me")

      get "/dashboard/senior/#{senior.id}"

      expect(doc.text.squish).to include("You're caring for Me")
      expect(doc.text.squish).to include("Caregiver view · Caring for Me")
      expect(warm?).to be(false)
    end
  end

  describe "the care receiver's screens" do
    it "names the device screen for its person, on the warm background" do
      get "/r/#{ReminderLink.mint(user: senior).token}"
      follow_redirect! while response.redirect?

      expect(doc.at_css("h1").text).to include("Mom's reminders")
      expect(doc.at_css("h1").text).not_to include("My Reminders")
      expect(warm?).to be(true)
    end

    it "names a signed-in care receiver's dashboard for them, on the warm background" do
      senior.update!(email: "mom@example.com")
      sign_in(senior)

      get "/dashboard"

      expect(doc.text.squish).to include("Mom's own screen")
      expect(doc.text.squish).to include("Mom's reminders")
      expect(doc.text).not_to include("Caregiver view")
      expect(warm?).to be(true)
    end
  end

  it "asks for the care receiver's name, not the caregiver's, when setting someone up" do
    sign_in(caregiver)

    get "/dashboard/care_receiver/new"

    expect(doc.text.squish).to include("Their name, not yours: the person who will get the reminders.")
  end
end
