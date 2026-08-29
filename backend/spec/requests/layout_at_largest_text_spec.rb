require "rails_helper"

# Found by looking at the app on a phone at the largest text size — the one
# combination none of the desktop renders covered. At 150% every element is half
# again as wide, and rows built as a non-wrapping flex put the buttons on top of
# the heading and pushed the action button off the right edge.
#
# These assert on the classes rather than on pixels, which is as close to a
# layout test as this suite can get: what they really pin is that these
# containers are allowed to wrap.
RSpec.describe "Layout that has to survive the largest text size", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam", text_size: :largest) }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)

  before { sign_in(caregiver) }

  it "scales the page for somebody who asked for the largest text" do
    get "/dashboard"

    expect(doc.at_css("html")[:style]).to eq("font-size: 150%")
  end

  it "lets the caregiver dashboard heading and its buttons stack" do
    get "/dashboard"

    header = doc.css("div").find { |d| d.at_css("h2") && d["class"].to_s.include?("flex") }

    expect(header["class"]).to include("flex-col")
    expect(header["class"]).to include("sm:flex-row")
  end

  it "lets the care receiver's page heading stack too" do
    get "/dashboard/senior/#{senior.id}"

    header = doc.css("div").find { |d| d.at_css("h2") && d["class"].to_s.include?("flex") }

    expect(header["class"]).to include("flex-col")
  end

  # The button was rendering as "Vie…" — a flex child will not shrink below its
  # content width without min-w-0, so the name column pushed its sibling out.
  it "lets the caregiver row wrap rather than clipping the action" do
    get "/dashboard"

    row = doc.css("div").find { |d| d["class"].to_s.include?("flex-wrap") && d.text.include?(senior.display_name) }

    expect(row).to be_present
    expect(row.at_css("div.min-w-0")).to be_present
  end

  it "says what the permission means rather than printing the stored word" do
    get "/dashboard"
    text = doc.text.gsub(/\s+/, " ")

    expect(text).to include("You can make changes")
    expect(text).not_to match(/\bManage\b/)
  end

  # Amber is the health warning. A second amber block under the same field meant
  # neither read as urgent.
  it "keeps the reminder form to one amber block" do
    senior.update!(spoken_language: "es-US")
    get "/dashboard/senior/#{senior.id}/reminder/new"

    ambers = doc.css("*").count { |n| n["class"].to_s =~ /\bbg-amber-50\b|\btext-amber-700\b/ }

    expect(ambers).to eq(1)
  end
end
