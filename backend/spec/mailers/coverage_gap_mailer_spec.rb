require "rails_helper"

RSpec.describe CoverageGapMailer, type: :mailer do
  let(:caregiver) { create(:user, :caregiver, name: "Care", email: "c@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:mail) { described_class.notify_gap(caregiver: caregiver, senior: senior, gaps: [ Date.new(2026, 8, 6) ]) }

  it "addresses the caregiver" do
    expect(mail.to).to eq([ caregiver.email ])
  end

  # Gmail and others override <a> link colors, which left the blue CTA buttons with
  # dark, hard-to-read text. Force white with an inline style on each button.
  it "gives the CTA buttons explicit white text" do
    expect(mail.body.encoded).to include('style="color: #ffffff')
    expect(mail.body.encoded.scan("color: #ffffff").size).to be >= 2
  end
end
