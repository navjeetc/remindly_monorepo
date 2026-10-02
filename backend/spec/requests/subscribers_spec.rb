require "rails_helper"

RSpec.describe "Subscribers", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def doc = Nokogiri::HTML(response.body)

  describe "POST /subscribers" do
    it "records the signup, unconfirmed, and asks them to check their inbox" do
      expect {
        post "/subscribers", params: { email: "ann@example.com", source: "home" }
      }.to change(Subscriber, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("Check your inbox")
      expect(Subscriber.last.source).to eq("home")
      expect(Subscriber.last).not_to be_confirmed
    end

    def confirmation_email = ActionMailer::Base.deliveries.find { |m| m.subject.to_s.start_with?("Confirm your") }

    # Double opt-in: a signup sends exactly one email, the confirmation, and
    # nothing to us. A bot typing in a stranger's address gets them one short
    # email and no more.
    it "sends only the confirmation email, and nothing to us" do
      expect {
        perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
      }.to change { ActionMailer::Base.deliveries.count }.by(1)

      expect(confirmation_email.to).to eq([ "ann@example.com" ])
      expect(confirmation_email.reply_to).to eq([ "hello@remindly.care" ])
      # A bot can ask again an hour later, so "you will not hear from us
      # again" would be untrue.
      expect(confirmation_email.body.encoded).not_to match(/not hear from us again/i)
      [ confirmation_email.text_part, confirmation_email.html_part ].each do |part|
        token = part.body.decoded[%r{/subscribers/confirm/([^"\s<]+)}, 1]
        expect(Subscriber.find_by_confirmation_token(token)).to eq(Subscriber.last)
      end
    end

    # Normalising on the way in is what makes the unique index mean anything.
    it "stores the address downcased and stripped" do
      post "/subscribers", params: { email: "  Ann@Example.COM " }

      expect(Subscriber.last.email).to eq("ann@example.com")
    end

    # People forget they signed up. Signing up twice should look exactly like
    # signing up once — not an error telling a stranger who else is on the list.
    context "when the address is already on the list" do
      before { Subscriber.create!(email: "ann@example.com", confirmed_at: 1.week.ago) }

      it "shows the same page without creating a duplicate" do
        expect {
          post "/subscribers", params: { email: "Ann@example.com" }
        }.not_to change(Subscriber, :count)

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("Check your inbox")
      end

      it "sends nothing at all" do
        expect {
          perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    # The form is the one way a stranger can make us email an address. Without
    # a limit, double opt-in would turn it into a way to flood somebody's
    # inbox with confirmation requests.
    context "when the address signed up and has not confirmed" do
      it "does not send another confirmation within the hour" do
        perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }

        expect {
          perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
        }.not_to change { ActionMailer::Base.deliveries.count }
      end

      # Simultaneous submissions each read the row before any had saved the
      # send time, and each sent an email. A stale copy of the row stands in
      # for the second request.
      it "sends one email when two requests race for the same address" do
        first = Subscriber.subscribe(email: "ann@example.com", source: "home")
        second = Subscriber.find(first.id)

        expect(first.request_confirmation).to be(true)
        expect(second.request_confirmation).to be(false)
        expect(enqueued_jobs.count { |job| job["arguments"].first == "SubscriberMailer" }).to eq(1)
      end

      it "sends a fresh one after an hour, for someone who lost the first" do
        perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }

        travel 61.minutes do
          expect {
            perform_enqueued_jobs { post "/subscribers", params: { email: "ann@example.com" } }
          }.to change { ActionMailer::Base.deliveries.count }.by(1)
        end
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

    # The page has to be true for a new signup, an unconfirmed one, someone
    # already on the list and a bot, and only some of those are sent an email.
    # It once promised the sheet was "on its way to your inbox", which sent a
    # returning subscriber hunting for a message that was never sent. So the
    # promise is conditional, and the sheet is linked right there.
    it "makes no unconditional promise of an email" do
      post "/subscribers", params: { email: "ann@example.com" }

      expect(response.body).not_to match(/on its way/i)
      expect(doc.text.squish).to include("If this address is not on the list yet")
      expect(doc.css("a").map { |a| a["href"] }).to include("/routine_sheet")
    end

    # A filled honeypot gets the success page and no record, so a bot has
    # nothing to learn from the difference.
    context "when the honeypot is filled" do
      it "records nothing but looks like success" do
        expect {
          post "/subscribers", params: { email: "bot@example.com", website: "http://spam.example" }
        }.not_to change(Subscriber, :count)

        expect(response).to have_http_status(:ok)
        expect(doc.at_css("h1").text).to include("Check your inbox")
      end

      it "sends nothing" do
        expect {
          perform_enqueued_jobs { post "/subscribers", params: { email: "bot@example.com", website: "x" } }
        }.not_to change { ActionMailer::Base.deliveries.count }
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
  describe "confirming a signup" do
    let!(:subscriber) { Subscriber.subscribe(email: "ann@example.com", source: "post:some-slug") }
    let(:token) { subscriber.confirmation_token }

    def welcome_email = ActionMailer::Base.deliveries.find { |m| m.subject.to_s.include?("routine sheet") }
    def notification = ActionMailer::Base.deliveries.find { |m| m.subject.to_s.start_with?("New Remindly subscriber") }

    # A mail scanner fetches every link in a message before anyone reads it.
    # If that fetch confirmed, anyone could still sign a stranger up.
    it "only shows a button when the link is opened" do
      get confirm_subscription_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("form[method='post'][action='/subscribers/confirm/#{token}'] button")).to be_present
      expect(subscriber.reload).not_to be_confirmed
    end

    it "joins the list when the button is pressed" do
      post confirm_subscription_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("You're on the list")
      expect(doc.css("a").map { |a| a["href"] }).to include("/routine_sheet")
      expect(subscriber.reload).to be_confirmed
    end

    it "sends the routine sheet to them, and tells us who joined and from which page" do
      perform_enqueued_jobs { post confirm_subscription_path(token: token) }

      expect(welcome_email.to).to eq([ "ann@example.com" ])
      # The welcome offers replying as well as the unsubscribe link; replies to
      # the default noreply@ sender would go nowhere.
      expect(welcome_email.reply_to).to eq([ "hello@remindly.care" ])
      expect(notification.subject).to include("ann@example.com")
      expect(notification.body.encoded).to include("post:some-slug")
      expect(notification.reply_to).to eq([ "ann@example.com" ])
    end

    it "sends them only once, however often the button is pressed" do
      perform_enqueued_jobs { post confirm_subscription_path(token: token) }

      expect {
        perform_enqueued_jobs { post confirm_subscription_path(token: token) }
      }.not_to change { ActionMailer::Base.deliveries.count }
      expect(response).to have_http_status(:ok)
      # So the page must not promise one either.
      expect(response.body).not_to match(/on its way/i)
    end

    it "says so when an already-used link is opened again" do
      subscriber.confirm!

      get confirm_subscription_path(token: token)

      expect(doc.at_css("h1").text).to include("You're on the list")
    end

    # The email says the link works for 7 days, and the address is deleted then.
    it "refuses an expired link and offers the form again" do
      token # minted now

      travel 8.days do
        post confirm_subscription_path(token: token)
      end

      expect(response).to have_http_status(:not_found)
      expect(doc.at_css("h1").text).to include("expired")
      expect(doc.at_css("form[action='/subscribers']")).to be_present
      # The hourly limit, or already being on the list, may mean no email.
      expect(response.body).not_to match(/on its way/i)
      expect(subscriber.reload).not_to be_confirmed
    end

    it "refuses a tampered link" do
      get confirm_subscription_path(token: "#{token}x")

      expect(response).to have_http_status(:not_found)
    end

    # An unsubscribe token must not double as a confirmation token: they are
    # signed for different purposes.
    it "refuses an unsubscribe token" do
      post confirm_subscription_path(token: subscriber.signed_id(purpose: :unsubscribe))

      expect(response).to have_http_status(:not_found)
      expect(subscriber.reload).not_to be_confirmed
    end

    # Same rules as every public page, and these carry a credential in their
    # address, so they must not be indexed or leak it in a Referer.
    it "issues no session cookie and keeps the token out of search and referrers" do
      get confirm_subscription_path(token: token)
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
      expect(doc.at_css("meta[name='robots']")["content"]).to include("noindex")
      expect(doc.at_css("link[rel='canonical']")).to be_nil

      post confirm_subscription_path(token: token)
      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
      expect(doc.at_css("meta[name='robots']")["content"]).to include("noindex")
    end

    it "does not record the token as a page view" do
      expect {
        get confirm_subscription_path(token: token)
        post confirm_subscription_path(token: token)
      }.not_to change(PageCount, :count)
    end
  end

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
