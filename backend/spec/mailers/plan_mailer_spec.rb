# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanMailer do
  let(:caregiver) do
    User.create!(email: "cg@example.com", role: :caregiver, name: "Priya", tz: "America/New_York",
                 family_granted_until: Time.zone.parse("2027-11-08 05:00"))
  end

  it "tells a beta caregiver about both plans and the date their free year ends" do
    mail = described_class.launch_notice(caregiver)

    expect(mail.to).to eq([ "cg@example.com" ])
    [ mail.text_part.decoded, mail.html_part.decoded ].each do |body|
      expect(body).to include("Hi Priya", "$9 a month or $79 a year", "November 8, 2027", "/billing")
    end
  end
end
