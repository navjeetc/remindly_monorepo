# frozen_string_literal: true

require "rails_helper"

# "Replace this link" and "Stop this link" were white boxes with a grey border,
# which is what a field looks like, and a caregiver took them for form fields.
# Nothing on them said what they did until they were pressed, and two of the
# three are hard to undo. Each now wears a filled button style and explains
# itself on hover.
RSpec.describe "The device link buttons", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def buttons
    Nokogiri::HTML(response.body).css("button").to_h { |b| [ b.text.squish, b ] }
  end

  it "explains each one and makes it look like a button" do
    ReminderLink.mint(user: senior)
    get "/dashboard/senior/#{senior.id}"

    { "Set up over the phone" => "button-secondary",
      "Replace this link" => "button-secondary",
      "Stop this link" => "button-danger" }.each do |label, variant|
      button = buttons.fetch(label)
      expect(button["title"]).to be_present, "#{label} has no tooltip"
      expect(button["class"].split).to include("button", variant), label
    end
  end

  it "explains the button that creates one" do
    get "/dashboard/senior/#{senior.id}"

    button = buttons.fetch("Create a device link")
    expect(button["title"]).to be_present
    expect(button["class"].split).to include("button", "button-primary")
  end
end
