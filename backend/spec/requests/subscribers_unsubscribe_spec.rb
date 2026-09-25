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
