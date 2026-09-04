# frozen_string_literal: true

require "rails_helper"

# A reminder link carries its credential in the address, so every place that
# records a URL is a place the credential can come to rest. The request log was
# the obvious one; analytics was not, and is worse — a log rotates, a table does
# not, and `ahoy_visits.landing_page` is rendered on the admin audit screen.
RSpec.describe "Where a reminder link's token comes to rest", type: :request do
  # Ahoy skips anything it takes for a bot, and a request with no user agent is
  # one — so a spec without this passes while recording nothing at all.
  #
  # A method rather than a constant: a constant assigned inside an RSpec block
  # lands on Object, and pages_spec.rb already has a BROWSER of its own. Mine
  # clobbered it, and four of its analytics specs started failing in the full
  # run while passing alone.
  def browser
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                           "(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36" }
  end

  let(:care_receiver) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let(:link) { ReminderLink.mint(user: care_receiver) }

  it "is not recorded as a visit" do
    expect {
      get "/r/#{link.token}", headers: browser
    }.not_to change { Ahoy::Visit.count }
  end

  it "appears in no landing page anywhere" do
    get "/r/#{link.token}", headers: browser

    expect(Ahoy::Visit.pluck(:landing_page).join(" ")).not_to include(link.token)
  end

  # The control: without this, excluding everything would pass the two above.
  # /login rather than a marketing page, which the analytics rules already
  # exclude so that anonymous visitors are never recorded at all.
  it "still records a visit to a page that is not a credential" do
    expect {
      get "/login", headers: browser
    }.to change { Ahoy::Visit.count }.by(1)
  end

  it "keeps the token out of the Rails request log" do
    expect(ActionDispatch::Request.new(Rack::MockRequest.env_for("/r/#{link.token}")).filtered_path)
      .to eq("/r/[FILTERED]")
  end
end
