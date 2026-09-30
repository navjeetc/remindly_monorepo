# frozen_string_literal: true

require "rails_helper"

# The sign-in form answered an iPhone with a 422 error page: Safari restored the
# tab with the form's authenticity token but not the session cookie that token
# belonged to. The token is still required; a stale one now leads back to the
# form with a fresh session instead of to a Rails error page.
#
# The test environment switches forgery protection off everywhere, which is why
# no spec caught this. It is switched back on here.
RSpec.describe "Requesting a sign-in link with a stale form", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "goes back to the form and says why, rather than showing a 422" do
    expect {
      post "/login/magic", params: { email: "nora@example.com", authenticity_token: "stale-token-from-a-restored-tab" }
    }.not_to change { ActionMailer::Base.deliveries.size }

    expect(response).to redirect_to(login_path)
    follow_redirect!
    expect(response.body).to include("That sign-in page had expired")
  end

  it "sends the link on the second try from the fresh form" do
    post "/login/magic", params: { email: "nora@example.com", authenticity_token: "stale" }
    follow_redirect!
    token = Nokogiri::HTML(response.body).at_css("input[name=authenticity_token]")["value"]

    expect {
      post "/login/magic", params: { email: "nora@example.com", authenticity_token: token }
    }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end
end
