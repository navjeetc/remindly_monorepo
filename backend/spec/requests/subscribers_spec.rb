require "rails_helper"

RSpec.describe "Subscribers", type: :request do
  def doc = Nokogiri::HTML(response.body)

  describe "POST /subscribers" do
    it "adds the address to the list and says so" do
      expect {
        post "/subscribers", params: { email: "ann@example.com", source: "home" }
      }.to change(Subscriber, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("You're on the list")
      expect(Subscriber.last.source).to eq("home")
    end

    it "sends the routine sheet to a new subscriber" do
      expect {
        perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(ActionMailer::Base.deliveries.last.to).to eq([ "ann@example.com" ])
    end

    # Normalising on the way in is what makes the unique index mean anything.
    it "stores the address downcased and stripped" do
      post "/subscribers", params: { email: "  Ann@Example.COM " }

      expect(Subscriber.last.email).to eq("ann@example.com")
    end

    # People forget they signed up. Signing up twice should look exactly like
    # signing up once — not an error telling a stranger who else is on the list.
    context "when the address is already subscribed" do
      before { Subscriber.create!(email: "ann@example.com") }

      it "shows the same success page without creating a duplicate" do
        expect {
          post "/subscribers", params: { email: "Ann@example.com" }
        }.not_to change(Subscriber, :count)

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("You're on the list")
      end

      it "does not send the welcome email a second time" do
        expect {
          perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    context "with an address that cannot work" do
      it "says so instead of silently dropping it" do
        expect {
          post "/subscribers", params: { email: "not-an-email" }
        }.not_to change(Subscriber, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to match(/didn't look right/i)
      end

      it "offers the form again so the address is not simply lost" do
        post "/subscribers", params: { email: "not-an-email" }

        expect(doc.at_css("form[action='/subscribers']")).to be_present
      end
    end

    # A filled honeypot gets the success page and no record, so a bot has
    # nothing to learn from the difference.
    context "when the honeypot is filled" do
      it "records nothing but looks like success" do
        expect {
          post "/subscribers", params: { email: "bot@example.com", website: "http://spam.example" }
        }.not_to change(Subscriber, :count)

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("You're on the list")
      end
    end

    # The reason CSRF protection is skipped: an authenticity token lives in the
    # session, and issuing a session cookie to anonymous readers of the public
    # pages is precisely what the marketing layout avoids.
    it "accepts a form with no authenticity token" do
      post "/subscribers", params: { email: "ann@example.com" }

      expect(response).to have_http_status(:ok)
    end

    it "issues no session cookie" do
      post "/subscribers", params: { email: "ann@example.com" }

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end
  end

  # The form has to actually be on the pages people read, or none of the above
  # ever runs.
  describe "the signup form" do
    it "appears on the homepage, the blog and the routine sheet" do
      [ "/", "/blog", "/routine_sheet" ].each do |path|
        get path

        expect(Nokogiri::HTML(response.body).at_css("form[action='/subscribers']")).to be_present,
          "no signup form on #{path}"
      end
    end

    # It records which page earned the address — the only way to find out which
    # writing is worth doing more of.
    it "tags each form with the page it is on" do
      get "/routine_sheet"

      source = Nokogiri::HTML(response.body).at_css("form[action='/subscribers'] input[name='source']")
      expect(source["value"]).to eq("routine_sheet")
    end
  end
end
