require "rails_helper"

# Remindly is built to sit below the point where it is holding medical records,
# and the only thing keeping it there is what people type into a title. The
# privacy policy says so, but nobody reads a policy while filling in a form.
#
# So the hint has to be on every surface that takes a title. A prompt on the
# reminder form alone would leave the task form — the one caregivers use most —
# quietly collecting the thing the policy promises is not collected.
RSpec.describe "The sensitive information hint", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)

  # Collapsed, because the sentence wraps in the template and a reader does not
  # care where. Asserting on the raw text would tie these specs to the line
  # breaks in an ERB file, which is how you get a spec that fails on a reflow.
  def page_text = doc.text.gsub(/\s+/, " ")

  # Matched on the sentence rather than a CSS hook, because what matters is
  # that a person reads it — a partial that renders into an invisible corner
  # would still satisfy a selector.
  def hint = page_text[/Please keep private health details out of this\./]

  before { sign_in(caregiver) }

  it "appears when a reminder is created" do
    get "/dashboard/senior/#{senior.id}/reminder/new"

    expect(hint).to be_present
  end

  it "appears when a reminder is edited, where an unsafe title gets fixed" do
    reminder = Reminder.create!(user: senior, title: "Morning pills", rrule: "FREQ=DAILY", tz: senior.tz)

    get "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}/edit"

    expect(hint).to be_present
  end

  it "appears on the task form, which takes free text the same way" do
    get "/seniors/#{senior.id}/tasks/new"

    expect(hint).to be_present
  end

  it "says what happens to the title, not merely that it is sensitive" do
    get "/dashboard/senior/#{senior.id}/reminder/new"

    # The reason is the whole argument: it is spoken aloud on the call, so a
    # medication name is overheard by whoever is in the room. Softening this
    # into "please be careful" would leave people with nothing to act on.
    expect(page_text).to include("read aloud on reminder calls")
  end

  it "does not block a title that happens to name a medication" do
    expect {
      post "/dashboard/senior/#{senior.id}/reminder", params: {
        reminder: { title: "Take Levodopa", rrule: "FREQ=DAILY", category: "medication" }
      }
    }.to change { Reminder.count }.by(1)
  end
end
