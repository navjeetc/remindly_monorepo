require "rails_helper"

RSpec.describe "Telnyx webhooks", type: :request do
  let(:senior) { create(:user, :senior, phone: "+15551234567", voice_reminders_enabled: true) }
  let(:reminder) { Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.current, status: :pending) }
  let(:telnyx_call) do
    TelnyxCall.create!(
      call_control_id: "call-123",
      call_leg_id: "leg-123",
      occurrence: occurrence,
      user: senior,
      status: "initiated",
      outcome: "pending"
    )
  end

  def telnyx_post(event_type, payload = {})
    post "/telnyx/webhooks",
      params: {
        token: "test-token",
        data: {
          event_type: event_type,
          payload: payload.merge(call_control_id: telnyx_call.call_control_id)
        }
      }
  end

  before do
    # These have to be stubbed in `before`, not `around`: rspec-mocks sets up its
    # per-example lifecycle after the around hook starts, so stubbing there
    # raises "doubles outside of the per-test lifecycle".
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)

    # TelnyxVoiceService reads credentials with dig, not the .telnyx reader.
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  it "gathers_using_speak the reminder when the call is answered" do
    telnyx_post("call.answered")

    expect(TelnyxVoiceService).to have_received(:gather_digit).once
    expect(telnyx_call.reload.status).to eq("answered")
    expect(telnyx_call.answered_at).to be_present
  end

  describe "what the call says" do
    def prompt_sent
      captured = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| captured = kw[:prompt] }
      telnyx_post("call.answered")
      captured
    end

    it "gives the title a sentence of its own, so an imperative title still reads correctly" do
      reminder.update!(title: "Take your morning vitamins")

      expect(prompt_sent).to eq(
        "Hello #{senior.display_name}. This is Remindly, with your reminder. " \
        "Take your morning vitamins. " \
        "Press 1 if you have done it. " \
        "Press 2 to be reminded again in 10 minutes."
      )
    end

    it "reads a noun-phrase title just as well" do
      reminder.update!(title: "Evening Insulin")

      expect(prompt_sent).to include("with your reminder. Evening Insulin. Press 1")
    end

    it "does not double the full stop when the title already ends in punctuation" do
      reminder.update!(title: "Take your pills.")

      said = prompt_sent

      expect(said).to include("Take your pills. Press 1")
      expect(said).not_to include("..")
    end

    it "names Remindly before asking for a keypress, because an unannounced robocall is the shape of a scam" do
      said = prompt_sent

      expect(said.index("Remindly")).to be < said.index("Press 1")
    end

    it "asks whether it was done, not whether it was taken -- not every reminder is a dose" do
      reminder.update!(title: "Drink a glass of water")

      said = prompt_sent

      expect(said).to include("Press 1 if you have done it")
      expect(said).not_to include("taken it")
    end
  end

  it "acknowledges the occurrence as taken when the senior presses 1" do
    telnyx_post("call.gather.ended", { "digits" => "1" })

    expect(telnyx_call.reload.outcome).to eq("taken")
    expect(occurrence.reload.status).to eq("acknowledged")
    expect(Acknowledgement.last.kind).to eq("taken")
  end

  describe "pressing 2" do
    it "snoozes rather than skips, matching the only two actions the senior UI offers" do
      telnyx_post("call.gather.ended", digits: "2")

      expect(telnyx_call.reload.outcome).to eq("snooze")
      expect(occurrence.acknowledgements.pluck(:kind)).to eq([ "snooze" ])
    end

    it "schedules the reminder again, so pressing 2 does not quietly cancel the dose" do
      telnyx_call # the lets are lazy; create the original occurrence before counting

      expect { telnyx_post("call.gather.ended", digits: "2") }
        .to change { reminder.occurrences.count }.by(1)

      later = reminder.occurrences.order(:scheduled_at).last
      expect(later.scheduled_at).to be_within(5.seconds).of(occurrence.scheduled_at + 10.minutes)
      expect(later.status).to eq("pending")
    end

    it "tells no caregiver it was done" do
      expect { telnyx_post("call.gather.ended", digits: "2") }
        .not_to have_enqueued_job(ReminderNotificationJob)
    end
  end


  it "rejects every webhook when no token is configured, rather than trusting them" do
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return(nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TELNYX_WEBHOOK_TOKEN").and_return(nil)

    telnyx_post("call.answered")

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects webhooks without the shared token" do
    post "/telnyx/webhooks",
      params: { data: { event_type: "call.answered", payload: { call_control_id: telnyx_call.call_control_id } } }

    expect(response).to have_http_status(:unauthorized)
  end
end
