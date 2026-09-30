# frozen_string_literal: true

require "rails_helper"

# A form for making something new starts with the cursor in the first field a
# person types into (docs/UI_STYLE_GUIDE.md). The reminder form did this and the task form did
# not, and a caregiver clicking New Task had to click again before typing.
# An edit form leaves the cursor alone: whoever opens one is as likely there
# to change something further down.
RSpec.describe "Where the cursor starts", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def focused
    Nokogiri::HTML(response.body).css("[autofocus]").map { |el| el["name"] }
  end

  it "is the title on a new task" do
    get "/seniors/#{senior.id}/tasks/new"

    expect(focused).to eq([ "task[title]" ])
  end

  it "is nowhere in particular when editing a task" do
    task = create(:task, senior: senior, created_by: caregiver)
    get "/seniors/#{senior.id}/tasks/#{task.id}/edit"

    expect(focused).to be_empty
  end

  # Optional, but start and end arrive filled in, so the reason is the only
  # thing left to type. The rule is the first field a person types into, not
  # the first field on the page.
  it "is the reason on a new blocked time" do
    get "/seniors/#{senior.id}/time_blocks/new"

    expect(focused).to eq([ "time_block[reason]" ])
  end

  it "is the pairing token when pairing" do
    get "/dashboard/pair"

    expect(focused).to eq([ "token" ])
  end

  it "is the name on the contact form" do
    get "/contact"

    expect(focused).to eq([ "name" ])
  end

  it "is the user ID when connecting Acuity" do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:external_scheduling).and_return(true)

    get "/seniors/#{senior.id}/scheduling_integrations/new"

    expect(focused).to eq([ "scheduling_integration[provider_user_id]" ])
  end

  it "is the address when inviting a caregiver" do
    get "/dashboard/senior/#{senior.id}/invite_caregiver"

    expect(focused).to eq([ "caregiver_email" ])
  end
end
