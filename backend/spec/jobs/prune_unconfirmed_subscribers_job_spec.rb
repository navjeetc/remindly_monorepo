# frozen_string_literal: true

require "rails_helper"

# The confirmation email and the privacy policy both say an address nobody
# confirms is deleted after a week.
RSpec.describe PruneUnconfirmedSubscribersJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  it "deletes signups left unconfirmed for longer than the confirmation window" do
    stale = travel_to(8.days.ago) { Subscriber.subscribe(email: "stale@example.com", source: "home") }
    fresh = travel_to(2.days.ago) { Subscriber.subscribe(email: "fresh@example.com", source: "home") }

    described_class.perform_now

    expect(Subscriber.exists?(stale.id)).to be(false)
    expect(Subscriber.exists?(fresh.id)).to be(true)
  end

  # A resend mints a link good for another seven days. Counting from the
  # signup deleted the row, and so killed that link, within hours.
  it "counts from the latest confirmation email, not the signup" do
    resent = travel_to(10.days.ago) { Subscriber.subscribe(email: "resent@example.com", source: "home") }
    travel_to(1.day.ago) { resent.request_confirmation }

    described_class.perform_now

    expect(Subscriber.exists?(resent.id)).to be(true)
  end

  it "deletes a row whose latest confirmation email is older than the window" do
    old = travel_to(10.days.ago) { Subscriber.subscribe(email: "old@example.com", source: "home").tap(&:request_confirmation) }

    described_class.perform_now

    expect(Subscriber.exists?(old.id)).to be(false)
  end

  # The link is minted when the mail job renders, which a backed-up queue can
  # delay. Its expiry is pinned to the send time this job counts from, so the
  # link never outlives the row it names.
  it "expires a link rendered late at the same moment the row becomes prunable" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home")
    subscriber.request_confirmation
    sent_at = subscriber.reload.confirmation_sent_at

    token = travel_to(sent_at + 3.days) { subscriber.confirmation_token }

    travel_to(sent_at + 7.days - 1.minute) do
      expect(Subscriber.find_by_confirmation_token(token)).to eq(subscriber)
    end
    travel_to(sent_at + 7.days + 1.minute) do
      expect(Subscriber.find_by_confirmation_token(token)).to be_nil
      described_class.perform_now
      expect(Subscriber.exists?(subscriber.id)).to be(false)
    end
  end

  it "never deletes anyone who confirmed, however long ago they signed up" do
    member = travel_to(1.year.ago) { Subscriber.create!(email: "ann@example.com", confirmed_at: Time.current) }

    described_class.perform_now

    expect(Subscriber.exists?(member.id)).to be(true)
  end

  # It never reached the CRM, so there is nothing there to remove.
  it "records no CRM removal and queues no sync for what it deletes" do
    travel_to(8.days.ago) { Subscriber.subscribe(email: "stale@example.com", source: "home") }
    clear_enqueued_jobs

    described_class.perform_now

    expect(CrmRemoval.count).to eq(0)
    expect(enqueued_jobs.map { |job| job["job_class"] }).not_to include("SyncSubscriberToCrmJob")
  end

  it "is scheduled to run every day in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "prune_unconfirmed_subscribers")

    expect(schedule).to include("class" => "PruneUnconfirmedSubscribersJob")
    expect(schedule["schedule"]).to match(/every day/)
  end
end
