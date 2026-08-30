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

  # The alert only ever fires from a call webhook, so the checkbox is inert for
  # anybody without phone reminders — which includes every care receiver in
  # development, where the feature is switched off. Saying nothing would let a
  # caregiver tick it for a dose that matters and believe they had bought fifty
  # minutes they had not.
  describe "when phone reminders are not set up" do
    it "says the checkbox will not do anything yet" do
      get "/dashboard/senior/#{senior.id}/reminder/new"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      expect(text).to include("This won't do anything yet")
      expect(text).to include("an hour after it was due")
    end

    it "still offers the checkbox, since it applies once calls are on" do
      get "/dashboard/senior/#{senior.id}/reminder/new"

      expect(Nokogiri::HTML(response.body).at_css("input[name='reminder[critical]']")).to be_present
    end
  end

  # Review caught this: the caveat covers two conditions but the copy named only
  # one, so a caregiver whose care receiver has a perfectly good verified number
  # was told they "don't have reminder calls set up" and would go and check a
  # phone setting that was never the problem.
  describe "when the phone is set up but the feature is switched off" do
    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)
      senior.update!(phone: "+15551234567", phone_verified_at: Time.current,
                     call_consent_at: Time.current, call_reminders_enabled: true)
    end

    it "blames the feature rather than this person's setup" do
      get "/dashboard/senior/#{senior.id}/reminder/new"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      expect(text).to include("This won't do anything yet")
      expect(text).to include("Reminder calls are switched off here")
      expect(text).not_to include("doesn't have reminder calls set up")
    end

    it "says the same thing on the edit form" do
      reminder = Reminder.create!(user: senior, title: "Levodopa", rrule: "FREQ=DAILY", tz: senior.tz)

      get "/dashboard/senior/#{senior.id}/reminder/#{reminder.id}/edit"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      expect(text).to include("Reminder calls are switched off here")
      expect(text).not_to include("doesn't have reminder calls set up")
    end
  end

  describe "when phone reminders are working" do
    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
      senior.update!(phone: "+15551234567", phone_verified_at: Time.current,
                     call_consent_at: Time.current, call_reminders_enabled: true)
    end

    it "drops the caveat" do
      get "/dashboard/senior/#{senior.id}/reminder/new"
      text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

      expect(text).not_to include("This won't do anything yet")
    end
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
