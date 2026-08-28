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

    it "may not be created" do
      sign_in(viewer)

      expect {
        post "/seniors/#{senior.id}/tasks",
          params: { task: { title: "Cardiologist", task_type: "appointment", status: "pending", priority: "medium" } }
      }.not_to change { Task.count }
    end

    it "may not be deleted" do
      task = Task.create!(senior: senior, created_by: manager, title: "Pills", status: :pending)
      sign_in(viewer)

      expect { delete "/seniors/#{senior.id}/tasks/#{task.id}" }.not_to change { Task.count }
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
    end

    it "is unaffected for a caregiver who manages" do
      sign_in(manager)

      expect {
        post "/dashboard/senior/#{senior.id}/reminder",
          params: { reminder: { title: "Morning pills", rrule: "FREQ=DAILY", category: "medication" } }
      }.to change { Reminder.count }.by(1)
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
