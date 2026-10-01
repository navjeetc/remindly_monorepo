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

  it "queues every current subscriber once GHL is configured" do
    allow(GoHighLevel).to receive(:configured?).and_return(true)
    Subscriber.subscribe(email: "ann@example.com", source: "home")
    Subscriber.subscribe(email: "bo@example.com", source: "blog_index")
    clear_enqueued_jobs

    expect { task.invoke }.to output(/Queued 2 subscribers/).to_stdout

    expect(enqueued_jobs.map { |job| job["arguments"] }).to contain_exactly([ "ann@example.com" ], [ "bo@example.com" ])
  end

  it "refuses to run before GHL is configured" do
    allow(GoHighLevel).to receive(:configured?).and_return(false)

    expect { task.invoke }.to raise_error(SystemExit).and output(/not configured/).to_stderr
  end
end
