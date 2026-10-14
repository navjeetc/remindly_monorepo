# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The sign-in page", type: :request do
  # Most visitors reach it from Sign in on the public site, and the only way
  # back used to be the How to page.
  it "links back to the home page" do
    get login_path

    expect(response).to have_http_status(:ok)
    home = Nokogiri::HTML(response.body).css("a").find { |a| a["href"] == root_path }
    expect(home&.text.to_s).to include("Remindly home page")
  end

  # It used to read only as a log-in screen ("Remindly Caregiver Dashboard",
  # "Send Magic Link"), so somebody who had just pressed "Set up reminders for my
  # parent" assumed they needed an account before they could make one.
  context "arriving from a button that says it is for a parent" do
    before { get login_path(for: "parent") }

    def doc = Nokogiri::HTML(response.body)

    it "greets them with what they asked to do, and says this is the sign-up" do
      expect(doc.at_css("h1").text).to include("Start setting up reminders for your parent")
      expect(doc.text).to include("New here? This creates your account.")
    end

    it "carries that into the request, so onboarding need not ask again" do
      expect(doc.at_css("form input[type=hidden][name=for]")&.[]("value")).to eq("parent")
    end
  end

  context "arriving any other way" do
    before { get login_path }

    def doc = Nokogiri::HTML(response.body)

    it "is the sign-in page, and still says the same link creates an account" do
      expect(doc.at_css("h1").text).to include("Sign in to Remindly")
      expect(doc.text).to include("The same link creates your account")
      expect(doc.at_css("input[name=for]")).to be_nil
    end
  end

  it "says what the button does rather than calling it a magic link" do
    get login_path

    expect(Nokogiri::HTML(response.body).at_css("input[type=submit]")["value"]).to eq("Email me a secure sign-in link")
    expect(response.body).not_to match(/magic link/i)
  end

  it "tells the person where the link went and what to do if it is not there" do
    post request_magic_link_path, params: { email: "ann@example.com" }
    follow_redirect!

    expect(response.body).to include("emailed a sign-in link to ann@example.com")
    expect(response.body).to include("check your spam folder")
  end
end
