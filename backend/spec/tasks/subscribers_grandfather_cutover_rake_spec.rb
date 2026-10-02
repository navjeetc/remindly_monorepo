# frozen_string_literal: true

require "rails_helper"
require "rake"

# Signups the old container took between the double opt-in migration and the
# cutover got the single opt-in treatment but an unconfirmed row.
RSpec.describe "subscribers:grandfather_cutover_signups" do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "subscribers:grandfather_cutover_signups" } }

  let(:task) { Rake::Task["subscribers:grandfather_cutover_signups"] }

  after { task.reenable }

  # The old code inserted a row and never set confirmation_sent_at.
  def old_code_signup(email) = travel_to(5.minutes.ago) { Subscriber.create!(email: email, source: "home") }

  it "confirms a signup the old code wrote after the migration" do
    straggler = old_code_signup("ann@example.com")

    expect { task.invoke }.to output(/Confirmed 1 signup from the cutover: ann@example.com/).to_stdout

    expect(straggler.reload).to be_confirmed
  end

  it "leaves alone a signup the new code is waiting on" do
    pending_row = travel_to(5.minutes.ago) { Subscriber.subscribe(email: "bo@example.com", source: "home").tap(&:request_confirmation) }

    expect { task.invoke }.to output(/Confirmed 0 signups from the cutover\./).to_stdout

    expect(pending_row.reload).not_to be_confirmed
  end

  it "leaves alone a row inserted in the last minute, whose confirmation email may not be recorded yet" do
    fresh = Subscriber.create!(email: "cy@example.com", source: "home")

    expect { task.invoke }.to output(/Confirmed 0 signups/).to_stdout

    expect(fresh.reload).not_to be_confirmed
  end

  # They already had the welcome email from the old code.
  it "sends them nothing" do
    old_code_signup("ann@example.com")

    expect { perform_enqueued_jobs { task.invoke } }.to output.to_stdout
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
