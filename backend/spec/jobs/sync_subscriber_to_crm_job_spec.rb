# frozen_string_literal: true

require "rails_helper"

# The job makes GHL match whether the address is on the list *when it runs*.
RSpec.describe SyncSubscriberToCrmJob do
  before { allow(GoHighLevel).to receive(:configured?).and_return(true) }

  it "subscribes an address that is on the list, with its source" do
    Subscriber.subscribe(email: "ann@example.com", source: "routine_sheet").tap(&:confirm!)
    expect(GoHighLevel).to receive(:subscribe).with(email: "ann@example.com", source: "routine_sheet")

    described_class.perform_now("ann@example.com")
  end

  it "unsubscribes an address that is not on the list" do
    expect(GoHighLevel).to receive(:unsubscribe).with(email: "ann@example.com")

    described_class.perform_now("ann@example.com")
  end

  # Double opt-in: an unconfirmed signup is not on the list. If one is ever
  # synced (someone left, then signed up again before the job ran), the job
  # must take them off, not put them back.
  it "unsubscribes an address that signed up but has not confirmed" do
    Subscriber.subscribe(email: "ann@example.com", source: "home")

    expect(GoHighLevel).not_to receive(:subscribe)
    expect(GoHighLevel).to receive(:unsubscribe).with(email: "ann@example.com")

    described_class.perform_now("ann@example.com")
  end

  # The bug review found: with three worker threads and delayed retries, the
  # subscribe job for someone who had since unsubscribed could run last and put
  # them back on the campaign list.
  it "leaves someone unsubscribed when their subscribe job runs after they left" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)
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

  it "clears the pending removal once the CRM has dropped the address" do
    CrmRemoval.record("ann@example.com")
    allow(GoHighLevel).to receive(:unsubscribe)

    described_class.perform_now("ann@example.com")

    expect(CrmRemoval.where(email: "ann@example.com")).to be_empty
  end

  it "keeps the pending removal when the CRM call fails, so the retry still knows" do
    CrmRemoval.record("ann@example.com")
    allow(GoHighLevel).to receive(:unsubscribe).and_raise(GoHighLevel::Error, "GHL GET /contacts/search/duplicate answered 503")

    described_class.perform_now("ann@example.com")

    expect(CrmRemoval.where(email: "ann@example.com")).to exist
  end

  # The gap review found: an unsubscribe while there were no credentials was
  # consumed as a no-op, and once the row was gone nothing remembered the
  # address still had to come out of the CRM.
  it "does nothing without credentials, leaving the pending removal for later" do
    allow(GoHighLevel).to receive(:configured?).and_return(false)
    CrmRemoval.record("ann@example.com")
    expect(GoHighLevel).not_to receive(:unsubscribe)

    described_class.perform_now("ann@example.com")

    expect(CrmRemoval.where(email: "ann@example.com")).to exist
  end
end
