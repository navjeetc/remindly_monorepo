require "rails_helper"

# The checkbox submitted and the controller dropped it: reminder_params
# permitted :critical, but create_reminder and update_reminder each build an
# explicit attribute hash and neither included it. So the flag could be ticked
# and never stored, and the whole feature was inert from the web forms.
#
# These drive the real endpoints rather than the model, because that gap lived
# entirely between the form and the writer.
RSpec.describe "Marking a reminder time-critical", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora", tz: "America/New_York") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  before do
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  it "stores the flag when the box is ticked" do
    post "/dashboard/senior/#{senior.id}/reminder",
      params: { reminder: { title: "Levodopa", category: "medication", critical: "1" } }

    expect(Reminder.last.critical).to be true
  end

  it "leaves it off when the box is not ticked" do
    post "/dashboard/senior/#{senior.id}/reminder",
      params: { reminder: { title: "Water", category: "hydration", critical: "0" } }

    expect(Reminder.last.critical).to be false
  end

  it "can be turned on later" do
    reminder = Reminder.create!(user: senior, title: "Levodopa", rrule: "FREQ=DAILY", tz: senior.tz)

    patch "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}",
      params: { reminder: { title: "Levodopa", category: "medication", critical: "1" } }

    expect(reminder.reload.critical).to be true
  end

  # Rails pairs a checkbox with a hidden "0", so unticking submits a value
  # rather than omitting the key. Testing for presence would have marked a
  # reminder critical permanently.
  it "can be turned off again" do
    reminder = Reminder.create!(user: senior, title: "Levodopa", rrule: "FREQ=DAILY",
                                tz: senior.tz, critical: true)

    patch "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}",
      params: { reminder: { title: "Levodopa", category: "medication", critical: "0" } }

    expect(reminder.reload.critical).to be false
  end
end
