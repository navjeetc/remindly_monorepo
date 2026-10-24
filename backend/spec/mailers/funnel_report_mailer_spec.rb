# frozen_string_literal: true

require "rails_helper"

RSpec.describe FunnelReportMailer, type: :mailer do
  include ActiveSupport::Testing::TimeHelpers

  def readable(mail)
    [ mail.html_part, mail.text_part ].map(&:decoded).join("\n")
  end

  # A Monday, as when the job runs. Last week is Mon Oct 12 to Sun Oct 18.
  let(:monday) { Date.new(2026, 10, 19) }

  around { |example| travel_to(monday.in_time_zone.change(hour: 12)) { example.run } }

  before do
    PageCount.create!(day: Date.new(2026, 10, 14), path: "/", referrer_host: "google.com", source: "google-a", bot: false, count: 12)
    PageCount.create!(day: Date.new(2026, 10, 14), path: "/setup-call", referrer_host: "", source: "", bot: false, count: 3)
    PageCount.create!(day: Date.new(2026, 10, 14), path: "/", referrer_host: "", source: "", bot: true, count: 99)
    PageCount.create!(day: 20.days.ago.to_date, path: "/", referrer_host: "bing.com", source: "", bot: false, count: 50)
    create(:user, :caregiver, signup_source: "google-a", first_signed_in_at: Time.current,
                              created_at: Time.zone.local(2026, 10, 14, 9))
  end

  let(:mail) { described_class.weekly }

  it "goes to the admin address" do
    expect(mail.to).to eq([ ApplicationMailer.admin_recipient ])
  end

  it "says the week's sign-ups and outside visits in the subject" do
    expect(mail.subject).to eq("Remindly last week: 1 sign-ups, 12 visits from other sites")
  end

  it "counts last week only, people only, and the setup-call clicks" do
    body = readable(mail)

    expect(body).to include("Page views (people, not bots): 15")
    expect(body).to include("Setup-call offer clicked: 3")
    expect(body).to include("google-a: 12")
    expect(body).not_to include("bing.com")
  end

  it "shows the sign-up funnel by tag" do
    expect(readable(mail)).to include("google-a: created 1, signed in 1")
  end

  # Copilot on #216: the report runs on Monday, and this Monday's activity
  # belongs to next week's report, not to both.
  it "leaves out the Monday it is sent on, and the Monday before last week" do
    PageCount.create!(day: monday, path: "/", referrer_host: "reddit.com", source: "", bot: false, count: 7)
    PageCount.create!(day: monday - 8, path: "/", referrer_host: "t.co", source: "", bot: false, count: 5)
    create(:user, :caregiver, signup_source: "meta-a", created_at: monday.in_time_zone.change(hour: 9))

    body = readable(mail)
    expect(body).not_to include("reddit.com")
    expect(body).not_to include("t.co")
    expect(body).not_to include("meta-a")
    expect(body).to include("Oct 12 to Oct 18")
  end

  it "is sent by the Monday job" do
    expect { WeeklyFunnelReportJob.perform_now }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end
