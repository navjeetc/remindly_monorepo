# frozen_string_literal: true

require "rails_helper"

# GHL telling Remindly that someone unsubscribed there. Without it, a recipient
# who used GHL's own unsubscribe link stayed a Subscriber here, contrary to the
# privacy policy, and reachable by the Rails monthly note.
RSpec.describe "CRM unsubscribe webhook", type: :request do
  include ActiveJob::TestHelper

  let(:secret) { "s3cret-for-ghl" }

  before { allow(GoHighLevel).to receive(:webhook_secret).and_return(secret) }

  def notify(**params)
    post "/crm/unsubscribes", params: params, as: :json
  end

  context "with the right secret" do
    it "removes the subscriber the same way Remindly's own unsubscribe does" do
      Subscriber.subscribe(email: "ann@example.com", source: "home")
      clear_enqueued_jobs

      notify(secret: secret, email: "Ann@Example.com ")

      expect(response).to have_http_status(:ok)
      expect(Subscriber.where(email: "ann@example.com")).to be_empty
      expect(CrmRemoval.where(email: "ann@example.com")).to exist
      expect(enqueued_jobs.map { |job| [ job["job_class"], job["arguments"] ] })
        .to include([ "SyncSubscriberToCrmJob", [ "ann@example.com" ] ])
    end

    it "accepts the email nested under contact" do
      Subscriber.subscribe(email: "ann@example.com", source: "home")

      notify(secret: secret, contact: { email: "ann@example.com" })

      expect(Subscriber.where(email: "ann@example.com")).to be_empty
    end

    # The answer must not reveal who is on the list.
    it "answers the same for an address that is not subscribed" do
      notify(secret: secret, email: "stranger@example.com")

      expect(response).to have_http_status(:ok)
      expect(CrmRemoval.count).to eq(0)
    end

    it "does nothing when no email is sent" do
      Subscriber.subscribe(email: "ann@example.com", source: "home")

      notify(secret: secret)

      expect(response).to have_http_status(:ok)
      expect(Subscriber.count).to eq(1)
    end
  end

  context "without the right secret" do
    before { Subscriber.subscribe(email: "ann@example.com", source: "home") }

    it "refuses a wrong secret and deletes nothing" do
      notify(secret: "guess", email: "ann@example.com")

      expect(response).to have_http_status(:unauthorized)
      expect(Subscriber.count).to eq(1)
    end

    it "refuses a missing secret" do
      notify(email: "ann@example.com")

      expect(response).to have_http_status(:unauthorized)
      expect(Subscriber.count).to eq(1)
    end

    # Until a secret is configured on purpose, nobody can use this to delete
    # subscribers, not even with an empty secret.
    it "refuses everything while no secret is configured" do
      allow(GoHighLevel).to receive(:webhook_secret).and_return(nil)

      notify(secret: "", email: "ann@example.com")

      expect(response).to have_http_status(:unauthorized)
      expect(Subscriber.count).to eq(1)
    end
  end
end
