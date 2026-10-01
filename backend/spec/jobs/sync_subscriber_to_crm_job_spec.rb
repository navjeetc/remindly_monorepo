# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSubscriberToCrmJob do
  it "subscribes in GHL" do
    expect(GoHighLevel).to receive(:subscribe).with(email: "ann@example.com", source: "home")

    described_class.perform_now(email: "ann@example.com", source: "home", change: "subscribed")
  end

  it "unsubscribes in GHL" do
    expect(GoHighLevel).to receive(:unsubscribe).with(email: "ann@example.com")

    described_class.perform_now(email: "ann@example.com", change: "unsubscribed")
  end

  it "retries when GHL refuses, rather than losing the change" do
    allow(GoHighLevel).to receive(:subscribe).and_raise(GoHighLevel::Error, "GHL POST /contacts/upsert answered 503")

    expect { described_class.perform_now(email: "ann@example.com", source: "home", change: "subscribed") }
      .to have_enqueued_job(described_class)
  end
end
