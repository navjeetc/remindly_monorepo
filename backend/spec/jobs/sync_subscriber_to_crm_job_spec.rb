# frozen_string_literal: true

require "rails_helper"

# The job makes GHL match whether the address is on the list *when it runs*.
RSpec.describe SyncSubscriberToCrmJob do
  it "subscribes an address that is on the list, with its source" do
    Subscriber.subscribe(email: "ann@example.com", source: "routine_sheet")
    expect(GoHighLevel).to receive(:subscribe).with(email: "ann@example.com", source: "routine_sheet")

    described_class.perform_now("ann@example.com")
  end

  it "unsubscribes an address that is not on the list" do
    expect(GoHighLevel).to receive(:unsubscribe).with(email: "ann@example.com")

    described_class.perform_now("ann@example.com")
  end

  # The bug review found: with three worker threads and delayed retries, the
  # subscribe job for someone who had since unsubscribed could run last and put
  # them back on the campaign list.
  it "leaves someone unsubscribed when their subscribe job runs after they left" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home")
    subscriber.destroy

    expect(GoHighLevel).not_to receive(:subscribe)
    expect(GoHighLevel).to receive(:unsubscribe).with(email: "ann@example.com")

    described_class.perform_now("ann@example.com") # the signup's job, running late
  end

  it "runs one job per address at a time" do
    expect(described_class.concurrency_limit).to eq(1)
    expect(described_class.new("ann@example.com").concurrency_key).to include("ann@example.com")
  end

  it "retries when GHL refuses or the network fails, rather than losing the change" do
    allow(GoHighLevel).to receive(:unsubscribe).and_raise(GoHighLevel::Error, "GHL GET /contacts/search/duplicate failed: Errno::ECONNRESET")

    expect { described_class.perform_now("ann@example.com") }.to have_enqueued_job(described_class)
  end
end
