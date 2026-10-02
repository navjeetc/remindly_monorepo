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
end
