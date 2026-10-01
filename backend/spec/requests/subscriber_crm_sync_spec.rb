# frozen_string_literal: true

require "rails_helper"

# Joining the list tags the contact in GoHighLevel; leaving it untags them.
# The job works out which by reading the table when it runs (see
# SyncSubscriberToCrmJob); this checks it is asked to at the right moments, and
# only those.
RSpec.describe "Syncing the mailing list to GoHighLevel", type: :request do
  include ActiveJob::TestHelper

  def sync_jobs
    enqueued_jobs.select { |job| job["job_class"] == "SyncSubscriberToCrmJob" }.map { |job| job["arguments"] }
  end

  it "asks for the contact to be tagged when someone joins" do
    post subscribers_path, params: { email: "Ann@Example.com", source: "home" }

    expect(sync_jobs).to eq([ [ "ann@example.com" ] ])
  end

  it "asks nothing of GHL when someone already on the list signs up again" do
    Subscriber.subscribe(email: "ann@example.com", source: "home")
    clear_enqueued_jobs

    post subscribers_path, params: { email: "ann@example.com", source: "home" }

    expect(sync_jobs).to be_empty
  end

  it "asks nothing of GHL for a bot that filled the honeypot" do
    post subscribers_path, params: { email: "bot@example.com", source: "home", website: "spam" }

    expect(sync_jobs).to be_empty
  end

  it "asks for the contact to be untagged when they unsubscribe" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home")
    clear_enqueued_jobs

    delete unsubscribe_path(token: subscriber.signed_id(purpose: :unsubscribe))

    expect(sync_jobs).to eq([ [ "ann@example.com" ] ])
  end
end
