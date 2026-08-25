require "rails_helper"

# A caregiver manages people, not addresses. These screens labelled the senior by
# email — so somebody looking after three parents read a column of mailboxes and
# had to translate each one back into a person.
#
# User#display_name already resolves this (nickname, then name, then email) and
# the caregiver dashboard's senior list already used it. These specs pin the rest
# of the screens to the same rule, and pin the one place an address is still the
# right thing to show.
RSpec.describe "How caregiver screens name a senior", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Margaret", email: "mum@example.com", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  before { sign_in(caregiver) }

  describe "the senior's page" do
    it "is headed by their name" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("Margaret")
    end

    # Kept, not dropped: it is the only unambiguous identifier when two seniors
    # share a first name, and a caregiver who needs to tell them apart has
    # nowhere else to look.
    it "still shows the address underneath" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("mum@example.com")
    end

    it "prefers a nickname over the full name, as display_name does" do
      senior.update!(nickname: "Mum")

      get senior_dashboard_path(senior)

      expect(response.body).to include("Mum")
    end
  end

  # display_name falls back to the email, so a senior with no name renders it as
  # the heading — and printing it again underneath reads as a bug rather than as
  # detail.
  describe "a senior with no name yet" do
    before { senior.update_columns(name: nil, nickname: nil) }

    it "falls back to the address rather than showing a blank heading" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("mum@example.com")
    end

    it "does not print the address twice" do
      get senior_dashboard_path(senior)

      expect(response.body.scan("mum@example.com").size).to eq(1)
    end
  end

  describe "the pages reached from there" do
    it "names the senior when creating a reminder" do
      get new_reminder_dashboard_path(senior)

      expect(response.body).to include("Create Reminder for Margaret")
    end

    it "names the senior when inviting another caregiver" do
      get invite_caregiver_dashboard_path(senior)

      expect(response.body).to include("Invite another caregiver to help with Margaret")
    end
  end

  # The exception, and it is not an oversight: this line is about where the
  # reminder email is delivered, so the address is the fact being stated.
  describe "the note about where reminders are sent" do
    it "still gives the address, because that is what it is talking about" do
      get new_reminder_dashboard_path(senior)

      expect(response.body).to include("Reminders will be sent to mum@example.com")
    end
  end
end
