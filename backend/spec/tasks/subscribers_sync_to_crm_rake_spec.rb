# frozen_string_literal: true

require "rails_helper"
require "rake"

# Sign-ups while the GHL sync is unconfigured are never queued for later, so
# this task is how GHL catches up once the credentials exist.
RSpec.describe "subscribers:sync_to_crm" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "subscribers:sync_to_crm" } }

  let(:task) { Rake::Task["subscribers:sync_to_crm"] }

  after { task.reenable }

  it "queues every confirmed subscriber once GHL is configured" do
    allow(GoHighLevel).to receive(:configured?).and_return(true)
    Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)
    Subscriber.subscribe(email: "bo@example.com", source: "blog_index").tap(&:confirm!)
    clear_enqueued_jobs

    Subscriber.subscribe(email: "unconfirmed@example.com", source: "home")

    expect { task.invoke }.to output(/Queued 2 subscribers and 0 removals/).to_stdout

    expect(enqueued_jobs.map { |job| job["arguments"] }).to contain_exactly([ "ann@example.com" ], [ "bo@example.com" ])
  end

  # Someone who unsubscribed while there were no credentials has no row left,
  # but may still be in the CRM (the hand-backfilled contacts are). The pending
  # removal is what lets the catch-up find them.
  it "also queues everyone who unsubscribed while the sync was dark" do
    allow(GoHighLevel).to receive(:configured?).and_return(true)
    Subscriber.subscribe(email: "gone@example.com", source: "home").tap(&:confirm!).destroy
    clear_enqueued_jobs

    expect { task.invoke }.to output(/Queued 0 subscribers and 1 removal\b/).to_stdout

    expect(enqueued_jobs.map { |job| job["arguments"] }).to eq([ [ "gone@example.com" ] ])
  end

  it "refuses to run before GHL is configured" do
    allow(GoHighLevel).to receive(:configured?).and_return(false)

    expect { task.invoke }.to raise_error(SystemExit).and output(/not configured/).to_stderr
  end
end
