require "rails_helper"

# A caregiver went straight past the title to the notes: the title input had
# the same thin border and no padding as everything else on the form, and the
# placeholder all but disappeared into it. The title is the one required field
# and the words the call speaks aloud, so the new-reminder form puts the cursor
# there. Editing does not — a caregiver opening an existing reminder is as
# likely there to move the time.
RSpec.describe "The reminder title field", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  before do
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  it "has the cursor on a new reminder" do
    get "/dashboard/senior/#{senior.id}/reminder/new"
    page = Nokogiri::HTML(response.body)

    expect(page.at_css("input[name='reminder[title]']")["autofocus"]).to be_present
    expect(page.css("[autofocus]").size).to eq(1)
  end

  it "does not take the cursor when editing" do
    reminder = Reminder.create!(user: senior, title: "Morning pills", rrule: "FREQ=DAILY", tz: senior.tz, start_time: Time.current)
    get "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("input[name='reminder[title]']")["autofocus"]).to be_nil
  end
end
