# frozen_string_literal: true

require "rails_helper"

# The unsubscribe link every subscriber email carries. Two requests, on
# purpose: GET only ever shows a confirm page, and DELETE — reachable only
# from the button on that page — is what actually removes the row. See the
# routes.rb comment on why: a bare GET that deleted on the spot is exactly
# what a corporate mail scanner or a link prefetcher fetches automatically,
# before anyone has read the message.
RSpec.describe "Unsubscribing", type: :request do
  def doc = Nokogiri::HTML(response.body)

  let!(:subscriber) { Subscriber.create!(email: "ann@example.com") }
  let(:token) { subscriber.signed_id(purpose: :unsubscribe) }

  describe "GET /subscribers/unsubscribe/:token" do
    it "shows a confirm page and removes nobody" do
      get "/subscribers/unsubscribe/#{token}"

      expect(response).to have_http_status(:ok)
      expect(doc.text).to include(subscriber.email)
      expect(Subscriber.exists?(subscriber.id)).to be(true)
    end

    # A prefetcher fetching this link must never be able to unsubscribe
    # someone who has not read the email yet, however many times it fetches.
    it "is safe to fetch any number of times" do
      3.times { get "/subscribers/unsubscribe/#{token}" }

      expect(Subscriber.exists?(subscriber.id)).to be(true)
    end

    # Nothing distinguishes "no such token" from "already used" — both answer
    # the terminal page directly, since there is nothing left to confirm.
    it "shows the terminal page for a token that does not resolve to anyone" do
      get "/subscribers/unsubscribe/not-a-real-token"

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("You're off the list")
    end

    it "issues no session cookie" do
      get "/subscribers/unsubscribe/#{token}"

      expect(response.headers["Set-Cookie"].to_s).not_to include("_backend_session")
    end

    # The confirm page's own form must point at this same token, or clicking
    # its button cannot possibly work.
    it "carries the token through to the confirm button" do
      get "/subscribers/unsubscribe/#{token}"

      form = doc.at_css("form")
      expect(form["action"]).to eq("/subscribers/unsubscribe/#{token}")
      expect(form.at_css("input[name='_method']")["value"]).to eq("delete")
    end
  end

  describe "DELETE /subscribers/unsubscribe/:token" do
    it "removes the subscriber and shows the terminal page" do
      expect {
        delete "/subscribers/unsubscribe/#{token}"
      }.to change(Subscriber, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(doc.at_css("h1").text).to include("You're off the list")
      expect(Subscriber.exists?(subscriber.id)).to be(false)
    end

    # Destroying the row makes the same token stop resolving to anyone, so a
    # second click — a double-tap, a retried request — is a no-op rather than
    # an error, and lands on the identical page.
    it "is idempotent" do
      delete "/subscribers/unsubscribe/#{token}"

      expect { delete "/subscribers/unsubscribe/#{token}" }.not_to change(Subscriber, :count)
      expect(response).to have_http_status(:ok)
    end

    it "does not remove anyone for an unknown token" do
      expect {
        delete "/subscribers/unsubscribe/not-a-real-token"
      }.not_to change(Subscriber, :count)

      expect(response).to have_http_status(:ok)
    end

    # A signed_id for a different purpose must not double as an unsubscribe
    # token — a subscriber has no other kind today, but the check has to name
    # the purpose rather than accept any signature this app has ever issued.
    it "refuses a token signed for a different purpose" do
      other_purpose_token = subscriber.signed_id(purpose: :something_else)

      expect {
        delete "/subscribers/unsubscribe/#{other_purpose_token}"
      }.not_to change(Subscriber, :count)
    end

    # No session-backed authenticity token protects this — the URL's token is
    # the entire credential, and a forged request achieves only what holding
    # that token already permits. Confirmed here the way the analogous create
    # spec confirms it for signup.
    it "accepts a request with no authenticity token" do
      delete "/subscribers/unsubscribe/#{token}"

      expect(response).to have_http_status(:ok)
    end
  end

  # A signup and an unsubscribe are not linked by anything but the address —
  # signing up again afterwards must work exactly like a first signup.
  it "can be followed by signing up again" do
    delete "/subscribers/unsubscribe/#{token}"

    expect {
      post "/subscribers", params: { email: subscriber.email }
    }.to change(Subscriber, :count).by(1)
  end
end

# The token in this address is exactly the case reminder_link_privacy_spec.rb
# already covers for /r/ — a credential in the URL comes to rest wherever URLs
# are recorded, and each of those places has to be found. This route adds one
# reminder_link_privacy_spec.rb never had to answer: it renders through
# PublicPage and the marketing layout, both built for pages with nothing to
# hide, so the page-view counter and the layout's own canonical/og:url tags
# needed the same treatment the request log and Ahoy already had.
RSpec.describe "Where the unsubscribe token comes to rest", type: :request do
  def browser
    { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
                           "(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36" }
  end

  let!(:subscriber) { Subscriber.create!(email: "ann@example.com") }
  let(:token) { subscriber.signed_id(purpose: :unsubscribe) }

  describe "analytics" do
    it "records no visit for the confirm page" do
      expect { get "/subscribers/unsubscribe/#{token}", headers: browser }
        .not_to change { Ahoy::Visit.count }
    end

    it "records no visit for the removal itself" do
      expect { delete "/subscribers/unsubscribe/#{token}", headers: browser }
        .not_to change { Ahoy::Visit.count }
    end

    it "appears in no landing page anywhere" do
      get "/subscribers/unsubscribe/#{token}", headers: browser

      expect(Ahoy::Visit.pluck(:landing_page).join(" ")).not_to include(token)
    end

    # The control: without excluding this path specifically, the two examples
    # above would pass by accident if credential_in_the_path? excluded nothing
    # and public_page? happened to catch it instead. /login rather than /faq —
    # /faq is itself excluded as a public page, which is a different rule for a
    # different reason and would prove nothing about credential_in_the_path?.
    it "still records a visit to a page that is not a credential" do
      expect { get "/login", headers: browser }.to change { Ahoy::Visit.count }.by(1)
    end
  end

  describe "the page-view counter" do
    it "does not count the confirm page" do
      expect { get "/subscribers/unsubscribe/#{token}", headers: browser }
        .not_to change { PageCount.sum(:count) }
    end

    it "does not count the removal itself" do
      expect { delete "/subscribers/unsubscribe/#{token}", headers: browser }
        .not_to change { PageCount.sum(:count) }
    end

    # Same reasoning as the Ahoy control above: proves the skip is scoped to
    # these two actions rather than to PublicPage generally.
    it "still counts an ordinary public page" do
      expect { get "/faq", headers: browser }.to change { PageCount.sum(:count) }.by(1)
    end
  end

  it "keeps the token out of the Rails request log" do
    expect(ActionDispatch::Request.new(Rack::MockRequest.env_for("/subscribers/unsubscribe/#{token}")).filtered_path)
      .to eq("/subscribers/unsubscribe/[FILTERED]")
  end

  describe "page metadata" do
    # Both pages carry the live token in their own address, so neither may
    # declare it as a canonical URL, publish it in Open Graph, or leak it
    # through a Referer header when a nav or footer link is followed.
    shared_examples "a page with nothing to declare about its own address" do
      it "sets noindex" do
        expect(doc.at_css("meta[name='robots']")&.[]("content")).to eq("noindex, nofollow")
      end

      it "restricts the referrer" do
        expect(doc.at_css("meta[name='referrer']")&.[]("content")).to eq("strict-origin")
      end

      it "declares no canonical URL" do
        expect(doc.at_css("link[rel='canonical']")).to be_nil
      end

      it "publishes no og:url" do
        expect(doc.at_css("meta[property='og:url']")).to be_nil
      end
    end

    def doc = Nokogiri::HTML(response.body)

    context "on the confirm page" do
      before { get "/subscribers/unsubscribe/#{token}" }

      include_examples "a page with nothing to declare about its own address"
    end

    context "on the terminal page" do
      before { delete "/subscribers/unsubscribe/#{token}" }

      include_examples "a page with nothing to declare about its own address"
    end

    # The control every example above needs: proves the layout still declares
    # a canonical URL for a page that has nothing to hide, so the credential
    # pages are opting out of something that is normally on, not something
    # that was already off.
    it "still declares a canonical URL and og:url on an ordinary page" do
      get "/faq"

      expect(doc.at_css("link[rel='canonical']")&.[]("href")).to eq("https://www.remindly.care/faq")
      expect(doc.at_css("meta[property='og:url']")&.[]("content")).to eq("https://www.remindly.care/faq")
      expect(doc.at_css("meta[name='robots']")).to be_nil
    end
  end
end
