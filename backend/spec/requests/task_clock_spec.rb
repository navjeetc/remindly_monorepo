require "rails_helper"

# A caregiver types "3:00 PM" into the task form meaning 3pm where the senior
# lives. Time.zone is UTC app-wide, so before this was fixed Rails cast that
# text to 15:00 UTC — and the senior's dashboard, which does convert, showed
# their cardiologist appointment at 11:00 AM. The caregiver's own list showed
# 3:00 PM only because it rendered the raw instant, cancelling one bug with
# another.
#
# So there are two halves here and both need holding: the instant that gets
# stored, and the wall clock every screen prints it back as.
RSpec.describe "The clock a task is set against", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  before { sign_in(caregiver) }

  def create_task(scheduled_at)
    post "/seniors/#{senior.id}/tasks", params: {
      task: { title: "Cardiologist", task_type: "appointment", status: "pending",
              priority: "medium", scheduled_at: scheduled_at }
    }
  end

  describe "creating one" do
    it "reads the typed time in the senior's clock, not in UTC" do
      create_task("2026-08-28T15:00")

      # 3pm in New York on 28 August is EDT, so 19:00 UTC. Storing 15:00 UTC
      # is the bug: it is 11am where she is.
      expect(Task.last.scheduled_at.utc.strftime("%Y-%m-%d %H:%M")).to eq("2026-08-28 19:00")
    end

    it "leaves an instant that already carries a zone alone" do
      # A calendar sync hands us an unambiguous time. Reinterpreting it would
      # shift every synced appointment by the senior's offset.
      task = senior.tasks_as_senior.create!(
        title: "From Acuity", task_type: "appointment", created_by: caregiver,
        external_source: "acuity", scheduled_at: Time.utc(2026, 8, 28, 15, 0)
      )

      expect(task.reload.scheduled_at.utc.hour).to eq(15)
    end
  end

  # Copilot and Codex both caught this on #102 and they were right: localizing
  # the form's pre-fill exposed that `new` was building its default in UTC, so
  # a New York senior opened the form on 5:00 AM and was one Save from meaning
  # it. The fix to the display half created the bug in the default.
  describe "the default on a new task" do
    it "offers 9am in the senior's clock, not 9am UTC" do
      get "/seniors/#{senior.id}/tasks/new"

      expect(response.body).to match(/value="\d{4}-\d{2}-\d{2}T09:00"/)
    end

    it "offers 9am in the senior's clock when they are not in the caregiver's" do
      pacific = create(:user, :senior, name: "Dad", tz: "America/Los_Angeles")
      CaregiverLink.create!(senior: pacific, caregiver: caregiver, permission: :manage)

      get "/seniors/#{pacific.id}/tasks/new"

      expect(response.body).to match(/value="\d{4}-\d{2}-\d{2}T09:00"/)
    end
  end

  describe "showing it back" do
    let!(:task) do
      senior.tasks_as_senior.create!(
        title: "Cardiologist", task_type: "appointment", created_by: caregiver,
        scheduled_at: ActiveSupport::TimeZone["America/New_York"].local(2026, 8, 28, 15, 0)
      )
    end

    it "prints the senior's wall clock on the caregiver's task list" do
      get "/seniors/#{senior.id}/tasks"

      expect(response.body).to include("03:00 PM")
      expect(response.body).not_to include("07:00 PM") # the raw UTC instant
    end

    it "prints the senior's wall clock on the task itself" do
      get "/seniors/#{senior.id}/tasks/#{task.id}"

      expect(response.body).to include("03:00 PM")
      expect(response.body).not_to include("07:00 PM")
    end

    # The round trip is the one that bites twice: open the form, change the
    # title, save, and the appointment must not walk four hours.
    it "survives being opened and saved again unchanged" do
      get "/seniors/#{senior.id}/tasks/#{task.id}/edit"
      expect(response.body).to include('value="2026-08-28T15:00"')

      patch "/seniors/#{senior.id}/tasks/#{task.id}", params: {
        task: { title: "Cardiologist follow-up", scheduled_at: "2026-08-28T15:00" }
      }

      expect(task.reload.scheduled_at.utc.hour).to eq(19)
    end
  end

  # task_params reinterprets start_time as well as scheduled_at, and until
  # Copilot pointed it out on #102 nothing exercised that. A recurring template
  # anchored an hour-offset out drags every occurrence it generates with it.
  describe "a recurring template" do
    it "anchors start_time in the senior's clock" do
      post "/seniors/#{senior.id}/tasks", params: {
        task: { title: "Morning walk", task_type: "activity", status: "pending",
                priority: "medium", rrule: "FREQ=DAILY", tz: senior.tz,
                start_time: "2026-08-28T09:00" }
      }

      template = Task.where.not(rrule: nil).last
      expect(template.start_time.utc.strftime("%H:%M")).to eq("13:00") # 9am EDT
    end

    it "generates occurrences on the senior's 9am, not UTC's" do
      post "/seniors/#{senior.id}/tasks", params: {
        task: { title: "Morning walk", task_type: "activity", status: "pending",
                priority: "medium", rrule: "FREQ=DAILY", tz: senior.tz,
                start_time: "2026-08-28T09:00" }
      }

      child = Task.where.not(parent_task_id: nil).first
      expect(child).to be_present
      expect(child.scheduled_at_local.strftime("%H:%M")).to eq("09:00")
    end
  end

  describe "a senior in a different zone from their caregiver" do
    let(:senior) { create(:user, :senior, name: "Dad", tz: "America/Los_Angeles") }

    it "uses the senior's clock, never the caregiver's" do
      create_task("2026-08-28T15:00")

      # 3pm Pacific is 22:00 UTC. If this reads 19:00 the code has reached for
      # Eastern — the caregiver's zone — instead of the senior's.
      expect(Task.last.scheduled_at.utc.strftime("%H:%M")).to eq("22:00")
    end
  end
end
