require "rails_helper"

RSpec.describe "Admin traffic report", type: :request do
  let(:admin) { create(:user, :caregiver, email: "admin@example.com", role: :admin) }
  let(:ordinary_user) { create(:user, :caregiver, email: "not-admin@example.com") }

  def sign_in_as(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  describe "who can see it" do
    it "turns away a signed-out visitor" do
      get "/admin/traffic"
      expect(response).to redirect_to(login_path)
    end

    # The report aggregates every public page view on the site. It is not
    # sensitive in the way the audit log is, but it is not everyone's business
    # either, and the guard is the same one the other admin pages use.
    it "turns away a signed-in user who is not an admin" do
      sign_in_as(ordinary_user)

      get "/admin/traffic"

      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to match(/admin/i)
    end

    it "lets an admin in" do
      sign_in_as(admin)

      get "/admin/traffic"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "what it reports" do
    before do
      PageCount.record!(path: "/faq", referrer: "https://www.reddit.com/r/x", user_agent: "Mozilla/5.0 Chrome/120")
      PageCount.record!(path: "/", source: "agingparents", user_agent: "Mozilla/5.0 Chrome/120")
      PageCount.record!(path: "/", user_agent: "Googlebot/2.1")

      sign_in_as(admin)
      get "/admin/traffic"
    end

    it "separates humans from crawlers" do
      expect(response.body).to include("Human views")
      expect(response.body).to include("Bots and crawlers")
    end

    it "names the site a human came from" do
      expect(response.body).to include("reddit.com")
    end

    it "shows the campaign tag from a link we shared" do
      expect(response.body).to include("agingparents")
    end

    it "lists the pages that were read" do
      expect(response.body).to include("/faq")
    end
  end

  # The page is reached before anything has been recorded, on the first deploy
  # and again after every prune. Empty states are the state it will most often
  # be seen in early on, so they should say something useful rather than break.
  it "renders with no data at all" do
    sign_in_as(admin)

    get "/admin/traffic"

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/Nothing yet|No human views/i)
  end

  # params[:days] reaches a date calculation, so it is worth knowing that
  # nonsense in the query string cannot 500 the page.
  it "survives a nonsense period in the query string" do
    sign_in_as(admin)

    [ "0", "-30", "abc", "999999" ].each do |days|
      get "/admin/traffic", params: { days: days }
      expect(response).to have_http_status(:ok), "days=#{days} broke the page"
    end
  end
end
