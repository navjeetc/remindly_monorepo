require "rails_helper"

RSpec.describe "Telnyx webhooks", type: :request do
  let(:senior) { create(:user, :senior, phone: "+15551234567", call_reminders_enabled: true) }
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

  # A reminder call opens with a line carrying no title, and the reminder itself
  # is spoken only once somebody presses a key -- a mailbox cannot, which is the
  # whole guarantee. So "a person answered" is two events: the pickup, and the
  # keypress that gets past the opening line.
  def answer_as_human
    telnyx_post("call.answered")
    telnyx_post("call.gather.ended", digits: "1")
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

  # Answering gets the opening line, which carries no title. The reminder itself
  # waits for a keypress, so answered_at -- which means "the reminder has been
  # spoken" -- is still empty here.
  it "gathers_using_speak the opening line when the call is answered" do
    telnyx_post("call.answered")

    expect(TelnyxVoiceService).to have_received(:gather_digit).once
    expect(telnyx_call.reload.status).to eq("answered")
    expect(telnyx_call.answered_at).to be_nil
  end

  describe "what the call says" do
    def prompt_sent
      captured = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| captured = kw[:prompt] }
      answer_as_human
      captured
    end

    it "gives the title a sentence of its own, so an imperative title still reads correctly" do
      reminder.update!(title: "Take your morning vitamins")

      expect(prompt_sent).to eq(
        "Hello #{senior.display_name}. This is Remindly, with your reminder. " \
        "Take your morning vitamins. " \
        "Press 1 if you have done it. " \
        "Press 2 to be reminded again in 10 minutes. " \
        "Press 9 to stop these calls."
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
    answer_as_human
    telnyx_post("call.gather.ended", { "digits" => "1" })

    expect(telnyx_call.reload.outcome).to eq("taken")
    expect(occurrence.reload.status).to eq("acknowledged")
    expect(Acknowledgement.last.kind).to eq("taken")
  end

  # Telnyx only re-sends an event it was not told was handled. Answering 200 to a
  # failed write throws the keypress away silently: the senior pressed 1, the
  # occurrence stays pending, and the caregiver is later emailed that she never
  # marked it done.
  describe "when handling a keypress fails" do
    it "answers with a retryable status rather than a cheerful 200" do
      allow(Acknowledgement).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "db gone")

      answer_as_human
      telnyx_post("call.gather.ended", digits: "1")

      expect(response).to have_http_status(:internal_server_error)
    end

    it "leaves the occurrence unacknowledged so the retry can still claim it" do
      allow(Acknowledgement).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "db gone")

      answer_as_human
      telnyx_post("call.gather.ended", digits: "1")

      expect(occurrence.reload.status).to eq("pending")
      expect(telnyx_call.reload.outcome).to eq("pending")
    end

    it "is safe to retry — a redelivered keypress acknowledges once, not twice" do
      answer_as_human
      2.times { telnyx_post("call.gather.ended", digits: "1") }

      expect(occurrence.acknowledgements.count).to eq(1)
      expect(occurrence.reload.status).to eq("acknowledged")
    end

    it "is safe to retry a snooze too" do
      telnyx_call # the lets are lazy; create the original occurrence before counting

      answer_as_human
      expect { 2.times { telnyx_post("call.gather.ended", digits: "2") } }
        .to change { reminder.occurrences.count }.by(1)

      expect(occurrence.acknowledgements.where(kind: :snooze).count).to eq(1)
    end
  end

  # Each of these is a way the provider could be told "handled" for work that
  # was not done, retiring an event that will never come again.
  describe "events that must stay redeliverable" do
    it "asks for a retry when the gather fails, rather than leaving the senior in silence" do
      allow(TelnyxVoiceService).to receive(:gather_digit).and_raise("Telnyx said no")

      answer_as_human

      expect(response).to have_http_status(:internal_server_error)
    end

    it "leaves answered_at unset when the gather failed, so the retry speaks" do
      allow(TelnyxVoiceService).to receive(:gather_digit).and_raise("Telnyx said no")

      answer_as_human

      expect(telnyx_call.reload.answered_at).to be_nil
    end

    # dial() can fail to persist call_control_id after Telnyx has accepted the
    # call, and its rescue loses the id for good — so a retry would never
    # correlate. The event carries client_state, which names the occurrence.
    it "adopts the reserved attempt when the call id is unknown but client_state names ours" do
      reserved = TelnyxCall.create!(occurrence: occurrence, user: senior, attempt_number: 1,
                                    call_control_id: nil, status: "reserved", outcome: "pending")

      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:not-recorded-yet",
            client_state: Base64.strict_encode64({ occurrence_id: occurrence.id, user_id: senior.id, attempt_number: 1 }.to_json)
          }
        }
      }

      expect(response).to have_http_status(:ok)
      expect(reserved.reload.call_control_id).to eq("v3:not-recorded-yet")

      # Posted directly rather than through telnyx_post: that helper references
      # the `telnyx_call` let, and instantiating it here would claim the same
      # (occurrence, attempt_number) as the reserved row and trip the unique
      # index. The id is the one just adopted. The keypress is what gets past
      # the opening line and makes the reminder itself be spoken.
      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.gather.ended",
          payload: { call_control_id: "v3:not-recorded-yet", digits: "1" }
        }
      }

      expect(reserved.reload.answered_at).to be_present
    end

    # Two numbers, one senior, one call_day. Verification attempt numbers restart
    # per destination, so both reservations are attempt 1 and every descriptive
    # field in client_state matches both rows. Matching on the description made
    # update_all try to give two rows one call_control_id: the unique index rolled
    # it back, correlate returned nothing, and the senior who had just answered
    # heard silence. The row id is the only identifier here that cannot collide.
    it "claims the exact verification attempt when another number holds the same attempt number" do
      day = Time.current.utc.to_date
      old_number = TelnyxCall.create!(user: senior, occurrence: nil, purpose: "verification",
                                      attempt_number: 1, to_number: "+15550000001", call_day: day,
                                      call_control_id: nil, status: "reserved", outcome: "pending")
      new_number = TelnyxCall.create!(user: senior, occurrence: nil, purpose: "verification",
                                      attempt_number: 1, to_number: "+15550000002", call_day: day,
                                      call_control_id: nil, status: "reserved", outcome: "pending")

      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:second-number",
            client_state: Base64.strict_encode64({ attempt_id: new_number.id, user_id: senior.id,
                                                   attempt_number: 1, call_day: day.to_s,
                                                   purpose: "verification" }.to_json)
          }
        }
      }

      expect(response).to have_http_status(:ok)
      expect(new_number.reload.call_control_id).to eq("v3:second-number")
      expect(old_number.reload.call_control_id).to be_nil
    end

    it "revives an attempt dial() had already given up on, since the provider says it is real" do
      TelnyxCall.create!(occurrence: occurrence, user: senior, attempt_number: 1,
                         call_control_id: nil, status: "failed", outcome: "error",
                         completed_at: Time.current)

      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.gather.ended",
          payload: {
            call_control_id: "v3:accepted-but-unrecorded",
            digits: "1",
            client_state: Base64.strict_encode64({ occurrence_id: occurrence.id, user_id: senior.id, attempt_number: 1 }.to_json)
          }
        }
      }

      revived = TelnyxCall.find_by(call_control_id: "v3:accepted-but-unrecorded")

      # The first digit got past the opening line; this is the one that answers
      # the reminder itself.
      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.gather.ended",
          payload: { call_control_id: "v3:accepted-but-unrecorded", digits: "1" }
        }
      }

      expect(occurrence.reload.status).to eq("acknowledged")
      expect(revived.reload.outcome).to eq("taken")
    end

    it "accepts and drops an unknown call that is not ours, rather than retrying forever" do
      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: { event_type: "call.answered", payload: { call_control_id: "v3:someone-elses" } }
      }

      expect(response).to have_http_status(:ok)
    end

    it "drops an event whose client_state names an occurrence that no longer exists" do
      post "/telnyx/webhooks", params: {
        token: "test-token",
        data: {
          event_type: "call.answered",
          payload: {
            call_control_id: "v3:not-recorded-yet",
            client_state: Base64.strict_encode64({ occurrence_id: 0, attempt_number: 1 }.to_json)
          }
        }
      }

      expect(response).to have_http_status(:ok)
    end

    # The window after the acknowledgement commits: if enqueueing failed, a
    # redelivery used to take the early return and the caregiver was never told.
    it "re-enqueues the caregiver notification on a redelivered keypress" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "1")

      expect { telnyx_post("call.gather.ended", digits: "1") }
        .to have_enqueued_job(ReminderNotificationJob).with(occurrence.id, "acknowledged")
    end

    it "still acknowledges only once when the keypress is redelivered" do
      answer_as_human
      2.times { telnyx_post("call.gather.ended", digits: "1") }

      expect(occurrence.acknowledgements.count).to eq(1)
    end
  end

  # completed_at is what TelnyxCall.call_in_flight? reads to decide whether this
  # senior may be called again. An attempt that has ended but never recorded it
  # blocks their next reminder for the whole in-flight window.
  describe "finishing a call" do
    it "records completion when nobody pressed anything" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "")

      expect(telnyx_call.reload.outcome).to eq("no_response")
      expect(telnyx_call.completed_at).to be_present
    end

    it "records completion on hangup even when a keypress already resolved it" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "1")
      telnyx_post("call.hangup")

      expect(telnyx_call.reload.outcome).to eq("taken")
      expect(telnyx_call.completed_at).to be_present
    end

    it "does not let a hangup overwrite an outcome a keypress decided" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "2")
      telnyx_post("call.hangup")

      expect(telnyx_call.reload.outcome).to eq("snooze")
    end

    it "records completion for a call nobody ever answered" do
      answer_as_human
      telnyx_post("call.hangup")

      expect(telnyx_call.reload.outcome).to eq("no_response")
      expect(telnyx_call.completed_at).to be_present
    end

    it "leaves the senior free to be called again once the call has ended" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "")

      expect(TelnyxCall.call_in_flight?(senior, Time.current)).to be false
    end
  end

  # Invariant 8 of the design document: the senior can stop the calls without
  # signing in, without a caregiver and without a screen. Offering that only on
  # the verification call would mean refusing at setup or never — and the call
  # they hear every day is the one they would actually want to stop.
  describe "pressing 9 on an ordinary reminder call" do
    it "stops future calls immediately and permanently" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "9")

      expect(senior.reload.call_opted_out_at).to be_present
      expect(senior.call_reminders_enabled).to be false
    end

    it "is offered aloud, not merely accepted" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw[:prompt] }

      answer_as_human

      expect(said).to include("Press 9 to stop these calls")
    end

    # They said stop calling, not that the dose was taken.
    it "leaves the occurrence pending so the missed sweep still claims it" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "9")

      expect(occurrence.reload.status).to eq("pending")
      expect(occurrence.acknowledgements).to be_empty
    end

    it "records the call as opted out rather than as no response" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "9")

      expect(telnyx_call.reload.outcome).to eq("opted_out")
    end
  end

  describe "pressing 2" do
    it "snoozes rather than skips, matching the only two actions the senior UI offers" do
      answer_as_human
      telnyx_post("call.gather.ended", digits: "2")

      expect(telnyx_call.reload.outcome).to eq("snooze")
      expect(occurrence.acknowledgements.pluck(:kind)).to eq([ "snooze" ])
    end

    it "schedules the reminder again, so pressing 2 does not quietly cancel the dose" do
      telnyx_call # the lets are lazy; create the original occurrence before counting

      answer_as_human
      expect { telnyx_post("call.gather.ended", digits: "2") }
        .to change { reminder.occurrences.count }.by(1)

      later = reminder.occurrences.order(:scheduled_at).last
      expect(later.scheduled_at).to be_within(5.seconds).of(occurrence.scheduled_at + 10.minutes)
      expect(later.status).to eq("pending")
    end

    it "tells no caregiver it was done" do
      answer_as_human
      expect { telnyx_post("call.gather.ended", digits: "2") }
        .not_to have_enqueued_job(ReminderNotificationJob)
    end
  end


  it "rejects every webhook when no token is configured, rather than trusting them" do
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return(nil)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TELNYX_WEBHOOK_TOKEN").and_return(nil)

    answer_as_human

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects webhooks without the shared token" do
    post "/telnyx/webhooks",
      params: { data: { event_type: "call.answered", payload: { call_control_id: telnyx_call.call_control_id } } }

    expect(response).to have_http_status(:unauthorized)
  end
end
