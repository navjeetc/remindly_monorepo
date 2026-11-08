# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "plans:grant_beta_family" do
  include ActiveSupport::Testing::TimeHelpers

  # Pinned to midday in New York. The cutoff is midnight there while
  # Date.current is UTC, so between UTC and New York midnight an account made
  # "now" fell before the cutoff and the test failed by the clock. (Copilot
  # on #227.)
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 11, 8, 12)) { example.run } }

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "plans:grant_beta_family" } }

  let(:task) { Rake::Task["plans:grant_beta_family"] }
  let!(:early) { User.create!(email: "early@example.com", role: :caregiver, name: "Early", created_at: 1.month.ago) }
  let!(:launch_morning) { User.create!(email: "morning@example.com", role: :caregiver, name: "Morning", created_at: 1.hour.ago) }
  let!(:late) { User.create!(email: "late@example.com", role: :caregiver, name: "Late", created_at: 1.day.from_now) }

  before { stub_const("Plan::LAUNCHED_ON", Date.current) }
  after { task.reenable }

  def run(confirm:)
    ENV["CONFIRM"] = confirm ? "yes" : nil
    expect { task.invoke }.to output.to_stdout
  ensure
    ENV.delete("CONFIRM")
  end

  it "changes nothing without CONFIRM=yes" do
    run(confirm: false)
    expect(early.reload.family_granted_until).to be_nil
  end

  it "gives accounts from before launch, and from launch day itself, a year of Family, and later ones nothing" do
    run(confirm: true)
    expect(early.reload.family_granted_until.to_date).to eq(Date.current + 12.months)
    expect(launch_morning.reload.family_granted_until.to_date).to eq(Date.current + 12.months)
    expect(late.reload.family_granted_until).to be_nil
  end
end

RSpec.describe "plans:send_launch_notice" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "plans:send_launch_notice" } }

  let(:task) { Rake::Task["plans:send_launch_notice"] }
  let!(:granted) do
    User.create!(email: "granted@example.com", role: :caregiver, name: "Granted", family_granted_until: 1.year.from_now)
  end

  before do
    # Not told: joined after launch, so no gift; a care receiver; an address
    # that bounces.
    User.create!(email: "new@example.com", role: :caregiver, name: "New")
    User.create!(email: "senior@example.com", role: :senior, name: "Rose", family_granted_until: 1.year.from_now)
    User.create!(email: "bounced@example.com", role: :caregiver, name: "Gone", family_granted_until: 1.year.from_now,
                 email_undeliverable_at: Time.current)
  end

  after { task.reenable }

  def run(confirm:)
    ENV["CONFIRM"] = confirm ? "yes" : nil
    expect { task.invoke }.to output.to_stdout
  ensure
    ENV.delete("CONFIRM")
  end

  it "sends nothing without CONFIRM=yes" do
    expect { run(confirm: false) }.not_to have_enqueued_mail
  end

  it "tells only the caregivers given the beta year" do
    expect { run(confirm: true) }.to have_enqueued_mail(PlanMailer, :launch_notice).once
      .with(granted)
  end
end
