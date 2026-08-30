# frozen_string_literal: true

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

    # Not shown as detail beside the timezone. Disambiguation belongs where a
    # caregiver chooses between people — the dashboard list, which shows the
    # address — and by this point they have chosen.
    #
    # "Not as detail" rather than "never": display_name falls back to the address
    # for a senior with no name, so it can still be the heading. The pair of
    # specs below covers that, and the two rules together are the whole
    # behaviour.
    it "does not show their email address alongside the timezone" do
      get senior_dashboard_path(senior)

      expect(response.body).not_to include("mum@example.com")
    end

    it "prefers a nickname over the full name, as display_name does" do
      senior.update!(nickname: "Mum")

      get senior_dashboard_path(senior)

      expect(response.body).to include("Mum")
    end
  end

  # display_name falls back to the email, so a senior with no name still gets a
  # heading rather than a blank one. That fallback is the only reason an address
  # appears on this page at all.
  describe "a senior with no name yet" do
    before { senior.update_columns(name: nil, nickname: nil) }

    it "falls back to the address rather than showing a blank heading" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("mum@example.com")
    end

    it "shows it once, as the heading, and not again as detail" do
      get senior_dashboard_path(senior)

      expect(response.body.scan("mum@example.com").size).to eq(1)
    end
  end

  describe "the pages reached from there" do
    it "names the senior when creating a reminder" do
      get new_reminder_dashboard_path(senior)

      expect(response.body).to include("Create Reminder for Margaret")
    end

    it "names the senior when editing one" do
      reminder = Reminder.create!(user: senior, title: "Take meds", category: :medication,
                                  rrule: "FREQ=DAILY", tz: senior.tz)

      get edit_reminder_dashboard_path(senior_id: senior.id, reminder_id: reminder.id)

      expect(response.body).to include("Edit Reminder for Margaret")
      expect(response.body).not_to include("Edit Reminder for mum@example.com")
    end

    it "names the senior when inviting another caregiver" do
      get invite_caregiver_dashboard_path(senior)

      expect(response.body).to include("Invite another caregiver to help with Margaret")
    end

    it "names the senior when creating a task" do
      get new_senior_task_path(senior_id: senior.id)

      expect(response.body).to include("Create a new task for Margaret")
    end
  end

  # Admin pages are the easiest to miss in UI-focused testing, and this one had
  # its own name-or-email expression that ignored nickname entirely — so a senior
  # known to everyone by a nickname appeared under their full name here and
  # nowhere else.
  describe "the admin user list" do
    let(:admin) { create(:user, :caregiver, name: "Root", email: "admin@example.com", role: :admin) }

    before do
      senior.update!(nickname: "Mum")
      sign_in(admin)
    end

    it "uses the same name the caregiver screens use" do
      get admin_users_path

      expect(response.body).to include("Mum")
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
