# frozen_string_literal: true

require "rails_helper"

# The offer of a free 15-minute call where we set Remindly up with a family. The
# booking itself is on GoHighLevel; this is the counted door to it.
RSpec.describe "Setup call offer", type: :request do
  def browser_ua
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end

  it "sends the visitor to the booking page" do
    get "/setup-call", headers: { "HTTP_USER_AGENT" => browser_ua }

    expect(response).to redirect_to(PagesController::SETUP_CALL_URL)
  end

  it "counts the click, since a redirect is not a page view" do
    expect { get "/setup-call", headers: { "HTTP_USER_AGENT" => browser_ua } }
      .to change { PageCount.humans.where(path: "/setup-call").sum(:count) }.by(1)
  end

  it "still redirects if counting fails" do
    allow(PageCount).to receive(:record!).and_raise(ActiveRecord::StatementInvalid)

    get "/setup-call"

    expect(response).to redirect_to(PagesController::SETUP_CALL_URL)
  end

  it "gives an anonymous visitor no cookie" do
    get "/setup-call", headers: { "HTTP_USER_AGENT" => browser_ua }

    # The net effect, as in page_counting_spec: Ahoy's cookies are set and then
    # cleared in the same response, and no session cookie is issued at all.
    %w[ahoy_visit ahoy_visitor].each do |name|
      expect(response.cookies[name]).to be_blank, "#{name} was left set"
    end
    expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
  end

  # Codex and Copilot on #216: Ahoy::Store only skipped pages that render, so
  # a click here wrote a visit row with the visitor's IP and browser.
  it "records no analytics visit for an anonymous visitor" do
    expect { get "/setup-call", headers: { "HTTP_USER_AGENT" => browser_ua } }
      .not_to change(Ahoy::Visit, :count)
  end

  it "is offered on the home page and the sign-in page" do
    get "/"
    expect(response.body).to include('href="/setup-call"')

    get "/login"
    expect(response.body).to include('href="/setup-call"')
  end

  # The hero offers one decision; a spec on .actions keeps it to one primary
  # button. The offer is a sentence beside it, never a second choice inside it.
  it "is not a button in the hero's actions" do
    get "/"

    actions = Nokogiri::HTML(response.body).at_css(".actions")
    expect(actions.to_html).not_to include("/setup-call")
  end
end
