require "rails_helper"

# "View" promised a restriction the code never applied: a caregiver holding it
# could create, edit and delete tasks, reminders and unavailability exactly like
# anybody else. Three checks guarded the phone panel and nothing guarded the
# rest, so the permission read like a safety mechanism while being decoration.
#
# Nobody holds view today — every link is manage since the pairing fix — so
# these specs guard a role that does not exist yet. That is the point. The
# alternative is leaving the name to be trusted by whoever adds one.
RSpec.describe "What a view-only caregiver may do", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora") }
  let(:viewer) { create(:user, :caregiver, name: "Val") }
  let(:manager) { create(:user, :caregiver, name: "Sam") }

  let!(:view_link) { CaregiverLink.create!(senior: senior, caregiver: viewer, permission: :view) }
  let!(:manage_link) { CaregiverLink.create!(senior: senior, caregiver: manager, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  describe "tasks" do
    it "may be read" do
      sign_in(viewer)
      get "/seniors/#{senior.id}/tasks"

      expect(response).to have_http_status(:ok)
    end

    # Asserting the refusal as well as the unchanged count. "Nothing was
    # created" is also true of a 500, so a count-only assertion would keep
    # passing while the endpoint started crashing instead of refusing.
    it "may not be created" do
      sign_in(viewer)

      expect {
        post "/seniors/#{senior.id}/tasks",
          params: { task: { title: "Cardiologist", task_type: "appointment", status: "pending", priority: "medium" } }
      }.not_to change { Task.count }

      expect(response).to redirect_to(senior_tasks_path(senior))
      expect(flash[:alert]).to include("not change them")
    end

    it "may not be deleted" do
      task = Task.create!(senior: senior, created_by: manager, title: "Pills", status: :pending)
      sign_in(viewer)

      expect { delete "/seniors/#{senior.id}/tasks/#{task.id}" }.not_to change { Task.count }

      expect(response).to redirect_to(senior_tasks_path(senior))
    end

    # The form is refused, not merely hidden. A gated button and an open
    # endpoint is the shape of every permission bug in this codebase so far.
    it "may not even open the form" do
      sign_in(viewer)
      get "/seniors/#{senior.id}/tasks/new"

      expect(response).to redirect_to(senior_tasks_path(senior))
    end

    it "is unaffected for a caregiver who manages" do
      sign_in(manager)

      expect {
        post "/seniors/#{senior.id}/tasks",
          params: { task: { title: "Cardiologist", task_type: "appointment", status: "pending", priority: "medium" } }
      }.to change { Task.count }.by(1)
    end
  end

  describe "reminders" do
    it "may not be created" do
      sign_in(viewer)

      expect {
        post "/dashboard/senior/#{senior.id}/reminder",
          params: { reminder: { title: "Morning pills", rrule: "FREQ=DAILY", category: "medication" } }
      }.not_to change { Reminder.count }

      expect(response).to redirect_to(senior_dashboard_path(senior))
      expect(flash[:alert]).to include("not change them")
    end

    it "is unaffected for a caregiver who manages" do
      sign_in(manager)

      expect {
        post "/dashboard/senior/#{senior.id}/reminder",
          params: { reminder: { title: "Morning pills", rrule: "FREQ=DAILY", category: "medication" } }
      }.to change { Reminder.count }.by(1)
    end
  end

  describe "unavailability" do
    it "may be read" do
      sign_in(viewer)
      get "/seniors/#{senior.id}/time_blocks"

      expect(response).to have_http_status(:ok)
    end

    it "may not be created" do
      sign_in(viewer)

      expect {
        post "/seniors/#{senior.id}/time_blocks",
          params: { time_block: { title: "Away", starts_at: 1.day.from_now, ends_at: 2.days.from_now } }
      }.not_to change { TimeBlock.count }

      expect(response).to redirect_to(senior_time_blocks_path(senior))
    end

    it "may not even open the form" do
      sign_in(viewer)
      get "/seniors/#{senior.id}/time_blocks/new"

      expect(response).to redirect_to(senior_time_blocks_path(senior))
    end
  end

  # The sharpest hole, and the reason the rest of this file matters: an
  # invitation creates a *manage* link. Without a guard a view-only caregiver
  # could invite an address they control, sign in as it, and hold everything
  # this release took away — bypassing every other check through the one
  # endpoint that hands out the permission being enforced.
  describe "inviting another caregiver" do
    it "may not be done at all" do
      invitee = create(:user, :caregiver, name: "Mallory", email: "mallory@example.com")
      sign_in(viewer)

      expect {
        post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: invitee.email }
      }.not_to change { CaregiverLink.count }

      expect(response).to redirect_to(senior_dashboard_path(senior))
      expect(flash[:alert]).to include("not invite other caregivers")
    end

    it "may not even open the form" do
      sign_in(viewer)
      get "/dashboard/senior/#{senior.id}/invite_caregiver"

      expect(response).to redirect_to(senior_dashboard_path(senior))
    end

    it "is unaffected for a caregiver who manages" do
      invitee = create(:user, :caregiver, name: "Alex", email: "alex@example.com")
      sign_in(manager)

      expect {
        post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: invitee.email }
      }.to change { CaregiverLink.count }.by(1)
    end
  end

  # The scheduling feature is switched off, so these run with it forced on: the
  # flag decides whether the door exists, not who may walk through it, and a
  # feature enabled months from now should not restore write access.
  describe "connected calendars" do
    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:external_scheduling).and_return(true)
    end

    it "may not be connected by a view-only caregiver" do
      sign_in(viewer)
      get "/seniors/#{senior.id}/scheduling_integrations/new"

      expect(response).to redirect_to(dashboard_path)
    end

    # An unresolvable senior is not permission to continue: create builds the
    # integration from @senior, so failing open would have written one with no
    # care receiver rather than refusing.
    it "refuses when the care receiver cannot be found, rather than continuing" do
      sign_in(manager)

      expect {
        post "/seniors/999999/scheduling_integrations",
          params: { scheduling_integration: { provider: "acuity" } }
      }.not_to change { SchedulingIntegration.count }

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "the care receiver themselves" do
    # They hold no permission at all — the column describes what a caregiver may
    # do, and the data is theirs.
    it "manages their own reminders regardless" do
      expect(senior.manages?(senior)).to be true
    end
  end
end
