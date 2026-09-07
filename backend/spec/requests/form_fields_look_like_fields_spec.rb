# frozen_string_literal: true

require "rails_helper"

# Every text field a caregiver types into was invisible.
#
# The markup said `border-gray-300`, which is a border *colour*, and never
# `border`, which is the width — and Tailwind's reset sets border-width to 0 on
# everything. So the colour was applied to a border that did not exist, and the
# reminder form rendered as two lines of placeholder text floating on white with
# nothing to show where to click. The selects beside them looked correct, which
# is what made it read as a design choice rather than a bug.
#
# Asserted rather than eyeballed because the failure is invisible in exactly the
# way that keeps it alive: nothing errors, nothing logs, and the page looks
# deliberate.
RSpec.describe "The fields a caregiver types into", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def typing_fields
    Nokogiri::HTML(response.body)
      .css("input[type=text], input[type=time], input[type=number], textarea, select")
  end

  # A field whose class list names a border colour and no border width is the
  # bug this spec exists for.
  def borderless(fields)
    fields.select do |field|
      classes = field["class"].to_s.split
      classes.any? { |c| c.start_with?("border-gray-", "border-blue-", "border-red-") } &&
        classes.none? { |c| c == "border" || c.start_with?("border-2", "border-4", "border-t", "border-b", "border-l", "border-r") }
    end
  end

  it "draws a box on the new reminder form" do
    get "/dashboard/senior/#{senior.id}/reminder/new"

    expect(borderless(typing_fields).map { |f| f["name"] }).to be_empty
  end

  it "draws a box on the edit reminder form" do
    reminder = Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)

    get "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}/edit"

    expect(borderless(typing_fields).map { |f| f["name"] }).to be_empty
  end

  it "draws a box on the task form" do
    get "/seniors/#{senior.id}/tasks/new"

    expect(borderless(typing_fields).map { |f| f["name"] }).to be_empty
  end
end
