require "rails_helper"

# Found by looking at the app on a phone at the largest text size — the one
# combination none of the desktop renders covered. At 150% every element is half
# again as wide, and rows built as a non-wrapping flex put the buttons on top of
# the heading and pushed the action button off the right edge.
#
# Each lookup is asserted present before its class is read: without that, a
# selector that stops matching fails as NoMethodError on nil rather than saying
# what went missing.
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

    expect(header).to be_present, "no flex container around the h2 — the heading markup moved"
    expect(header["class"]).to include("flex-col")
    expect(header["class"]).to include("sm:flex-row")
  end

  it "lets the care receiver's page heading stack too" do
    get "/dashboard/senior/#{senior.id}"

    header = doc.css("div").find { |d| d.at_css("h2") && d["class"].to_s.include?("flex") }

    expect(header).to be_present, "no flex container around the h2 — the heading markup moved"
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

  # The whole row was an <a> wrapping the "View", "Coverage" and "Unlink"
  # controls. Invalid HTML, and every control was reachable twice by keyboard —
  # which matters most to exactly the people who turn the text size up.
  it "does not put the row's controls inside a link" do
    get "/dashboard"

    expect(doc.css("a a")).to be_empty
    expect(doc.css("a form")).to be_empty
  end

  it "still lets the care receiver's name open their page" do
    get "/dashboard"
    name_link = doc.css("a").find { |a| a.text.strip == senior.display_name }

    expect(name_link).to be_present
    expect(name_link["href"]).to eq("/dashboard/senior/#{senior.id}")
  end

  it "says what the permission means rather than printing the stored word" do
    get "/dashboard"
    text = doc.text.gsub(/\s+/, " ")

    expect(text).to include("You can make changes")
    expect(text).not_to match(/\bManage\b/)
  end

  # Amber is for the one caution on this form. Asserted by finding each block by
  # its own words and checking which is styled as a warning, rather than by
  # counting nodes carrying a particular utility class — that version broke if
  # somebody moved amber-700 to amber-800, which changes nothing about the
  # hierarchy this is here to protect.
  describe "the reminder form's warning hierarchy" do
    before do
      senior.update!(spoken_language: "es-US")
      get "/dashboard/senior/#{senior.id}/reminder/new"
    end

    # Whitespace collapsed before matching: the ERB wraps these sentences, so
    # the raw node text carries newlines mid-phrase and a literal include? finds
    # nothing. Same trap as the "read aloud on reminder calls" assertion in the
    # sensitive-info specs.
    def block_containing(text)
      doc.css("p, div").reverse.find { |n| n.text.gsub(/\s+/, " ").include?(text) }
    end

    it "keeps the health warning amber, because it is the caution" do
      warning = block_containing("keep private health details out")

      expect(warning).to be_present, "the health warning is gone from the form"
      expect(warning["class"]).to match(/amber/)
    end

    it "does not shout the language note as well" do
      note = block_containing("read out exactly as you type it")

      expect(note).to be_present, "the spoken-title note is gone from the form"
      expect(note["class"]).not_to match(/amber/)
      expect(note["class"]).to match(/gray/)
    end
  end
end
