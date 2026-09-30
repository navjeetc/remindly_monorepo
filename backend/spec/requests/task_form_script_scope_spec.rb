# frozen_string_literal: true

require "rails_helper"

# Every repeating task failed to save with "Start time can't be blank", from
# 2026-08-27 until this was caught. The task form has two <script> blocks. The
# first declared SENIOR_TODAY inside its DOMContentLoaded handler, and the
# second (the recurrence builder) used it: choosing a repeat pattern set
# rrule, threw a ReferenceError on SENIOR_TODAY, and never set start_time.
#
# Request specs run no JavaScript, so this checks the shape that broke: the
# constants the recurrence builder shares must be declared at the top of a
# script, before any handler, where both blocks can see them.
RSpec.describe "The task form's shared script constants", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  it "declares SENIOR_TODAY where the recurrence builder can reach it" do
    get "/seniors/#{senior.id}/tasks/new"
    scripts = Nokogiri::HTML(response.body).css("script").map(&:text)

    declaring = scripts.find { |script| script.include?("const SENIOR_TODAY") }
    expect(declaring).to be_present
    expect(declaring.index("const SENIOR_TODAY")).to be < declaring.index("addEventListener"),
      "SENIOR_TODAY is declared inside a handler, out of reach of the other script block"

    using = scripts.find { |script| script.include?("${SENIOR_TODAY}") }
    expect(using).to be_present
  end
end
