# frozen_string_literal: true

require "rails_helper"

# The policy asks people to keep clinical detail out of Remindly, and is candid
# that nothing stops them: titles are free text and whatever is typed is stored.
# That makes the notice on the form the only thing doing real work, because
# nobody reads a policy while filling in a form.
#
# So it has to be on every surface that takes a title — a prompt on the reminder
# form alone would leave the task form, the one caregivers use most, collecting
# exactly what the policy asks them not to write.
#
# And it has to be true on each of them. A reminder title is spoken aloud by the
# call; a task title is only ever read. Telling somebody their task is announced
# down a phone line would be teaching them something false about their own data.
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
  def hint = page_text[/Please keep private health details out of this (reminder|task)/]

  # The notes and description boxes get the quiet version. They cannot go
  # uncovered — a field labelled "Additional details" is where a dosage ends up,
  # and the privacy policy asks for titles *and* notes — but a second amber
  # panel would turn the task form into a wall of warnings.
  def asides = page_text.scan("Same here — keep clinical detail out.").length

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

  # Tasks never reach TelnyxWebhooksController#announcement_for — it speaks
  # reminder.title and nothing else — so claiming otherwise here would be a
  # false statement about where their words end up.
  it "does not tell the task form its titles are spoken aloud" do
    get "/seniors/#{senior.id}/tasks/new"

    expect(page_text).to include("can read it on their own dashboard")
    expect(page_text).not_to include("read aloud")
  end

  it "covers the reminder notes box, not only the title" do
    get "/dashboard/senior/#{senior.id}/reminder/new"

    expect(asides).to eq(1)
  end

  it "covers both free-text boxes on the task form" do
    get "/seniors/#{senior.id}/tasks/new"

    # description and notes
    expect(asides).to eq(2)
  end

  it "asks for the whole record, since the notes box is where detail lands" do
    get "/dashboard/senior/#{senior.id}/reminder/new"

    expect(page_text).to include("out of this reminder, here and in the notes below")
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
