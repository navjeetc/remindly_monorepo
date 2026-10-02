# frozen_string_literal: true

require "rails_helper"

# Confirming a place on the list tags the contact in GoHighLevel; leaving it
# untags them. Signing up without confirming reaches GHL not at all.
# The job works out which by reading the table when it runs (see
# SyncSubscriberToCrmJob); this checks it is asked to at the right moments, and
# only those.
RSpec.describe "Syncing the mailing list to GoHighLevel", type: :request do
  include ActiveJob::TestHelper

  def sync_jobs
    enqueued_jobs.select { |job| job["job_class"] == "SyncSubscriberToCrmJob" }.map { |job| job["arguments"] }
  end

  it "asks nothing of GHL when someone signs up, before they confirm" do
    post subscribers_path, params: { email: "Ann@Example.com", source: "home" }

    expect(sync_jobs).to be_empty
  end

  it "asks for the contact to be tagged when they confirm" do
    post subscribers_path, params: { email: "Ann@Example.com", source: "home" }
    subscriber = Subscriber.find_by!(email: "ann@example.com")

    post confirm_subscription_path(token: subscriber.confirmation_token)

    expect(sync_jobs).to eq([ [ "ann@example.com" ] ])
  end

  it "asks nothing of GHL when an unconfirmed signup is deleted" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home")
    clear_enqueued_jobs

    subscriber.destroy

    expect(sync_jobs).to be_empty
    expect(CrmRemoval.where(email: "ann@example.com")).to be_empty
  end

  it "asks nothing of GHL when someone already on the list signs up again" do
    Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)
    clear_enqueued_jobs

    post subscribers_path, params: { email: "ann@example.com", source: "home" }

    expect(sync_jobs).to be_empty
  end

  it "asks nothing of GHL for a bot that filled the honeypot" do
    post subscribers_path, params: { email: "bot@example.com", source: "home", website: "spam" }

    expect(sync_jobs).to be_empty
  end

  it "asks for the contact to be untagged when they unsubscribe" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)
    clear_enqueued_jobs

    delete unsubscribe_path(token: subscriber.signed_id(purpose: :unsubscribe))

    expect(sync_jobs).to eq([ [ "ann@example.com" ] ])
    expect(CrmRemoval.where(email: "ann@example.com")).to exist
  end

  it "forgets a pending removal when the address joins again and confirms" do
    Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!).destroy

    post subscribers_path, params: { email: "ann@example.com", source: "routine_sheet" }
    expect(CrmRemoval.where(email: "ann@example.com")).to exist

    Subscriber.find_by!(email: "ann@example.com").confirm!
    expect(CrmRemoval.where(email: "ann@example.com")).to be_empty
  end

  # Signing up again is only a request. Had it erased the pending removal of
  # someone who just left, and the CRM been unreachable, nothing would ever
  # have deleted them there.
  it "keeps a pending removal when someone who left signs up again without confirming" do
    Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!).destroy

    post subscribers_path, params: { email: "ann@example.com", source: "home" }

    expect(CrmRemoval.where(email: "ann@example.com")).to exist
  end

  # Review found the pending removal was written after commit, so a quick
  # leave-and-rejoin could apply the two writes out of order. They now ride in
  # the subscriber's own transaction: if the change does not happen, neither
  # does the bookkeeping.
  it "writes the pending removal in the same transaction as the unsubscribe" do
    subscriber = Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)

    Subscriber.transaction do
      subscriber.destroy
      expect(CrmRemoval.where(email: "ann@example.com")).to exist
      raise ActiveRecord::Rollback
    end

    expect(Subscriber.where(email: "ann@example.com")).to exist
    expect(CrmRemoval.where(email: "ann@example.com")).to be_empty
  end

  it "clears a pending removal in the same transaction as the confirmation" do
    CrmRemoval.record("ann@example.com")

    Subscriber.transaction do
      Subscriber.subscribe(email: "ann@example.com", source: "home").tap(&:confirm!)
      expect(CrmRemoval.where(email: "ann@example.com")).to be_empty
      raise ActiveRecord::Rollback
    end

    expect(CrmRemoval.where(email: "ann@example.com")).to exist
  end

  # The policy used to say the address went to Postmark and nobody else. It
  # has to disclose the CRM before this sync is switched on. It says "our CRM"
  # rather than naming the vendor, by the owner's choice.
  it "is disclosed in the privacy policy" do
    get "/privacy"
    text = Nokogiri::HTML(response.body).text.squish

    expect(text).to include("also kept in our CRM")
    expect(text).to include("nothing goes to our CRM, until you do")
    expect(text).to include("including from our CRM")
  end
end
