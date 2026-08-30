# frozen_string_literal: true

require "rails_helper"

RSpec.describe CoverageGapMailer, type: :mailer do
  let(:caregiver) { create(:user, :caregiver, name: "Care", email: "c@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let(:mail) { described_class.notify_gap(caregiver: caregiver, senior: senior, gaps: [ Date.new(2026, 8, 6) ]) }

  it "addresses the caregiver" do
    expect(mail.to).to eq([ caregiver.email ])
  end

  # Gmail and others override <a> link colors, which left the blue CTA buttons with
  # dark, hard-to-read text. Force white with an *inline* style on each button —
  # exactly one per button, so this can't be satisfied by the .button CSS rule alone.
  it "gives both CTA buttons explicit inline white text" do
    expect(mail.body.encoded.scan('style="color: #ffffff').size).to eq(2)
  end

  it "tells the caregiver how to turn these emails off" do
    expect(mail.body.encoded).to match(/turn these coverage-gap emails off/i)
    expect(mail.body.encoded).to include("/profile") # links to notification settings
  end
end
