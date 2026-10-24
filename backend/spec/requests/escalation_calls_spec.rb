# frozen_string_literal: true

require "rails_helper"

# Escalation calls: the care receiver did not answer any of the calls for a
# time-critical reminder, so Remindly rings their caregivers in the family's
# order until one presses 1 to say they will check.
RSpec.describe "Escalation calls", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  # Mid-morning in New York, inside everyone's calling hours.
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  let(:senior) do
    create(:user, :senior, name: "Mom", phone: "+15551234567", tz: "America/New_York",
           call_consent_at: 1.week.ago, phone_verified_at: 1.week.ago, call_reminders_enabled: true)
  end
  let(:reminder) do
    Reminder.create!(user: senior, title: "Insulin", category: :medication, rrule: "FREQ=DAILY",
                     tz: senior.tz, critical: true)
  end
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: 20.minutes.ago, status: :pending) }

  def confirmed_caregiver(name, phone, position)
    create(:user, :caregiver, name: name, email: "#{name.downcase}@example.com", phone: phone,
           tz: "America/New_York", escalation_consent_at: 1.day.ago).tap do |caregiver|
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, escalation_position: position)
    end
  end

  let!(:first) { confirmed_caregiver("Christy", "+15715550101", 1) }
  let!(:second) { confirmed_caregiver("Navjeet", "+15715550102", 2) }

  let(:flags) { { phone_call_reminders: true, escalation_calls: true } }

  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    flags.each { |name, on| allow(FeatureFlag).to receive(:enabled?).with(name).and_return(on) }

    allow(TelnyxVoiceService).to receive(:escalate) do |attempt|
      attempt.update!(call_control_id: "esc-#{attempt.id}", status: "initiated")
      "esc-#{attempt.id}"
    end
    allow(TelnyxVoiceService).to receive(:gather_digit)
    allow(TelnyxVoiceService).to receive(:hangup)
    allow(TelnyxVoiceService).to receive(:hangup!)
    allow(TelnyxVoiceService).to receive(:speak).and_return({ "data" => { "result" => "ok" } })
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(nil)
  end

  def telnyx_post(call, event_type, payload = {})
    post "/telnyx/webhooks",
      params: { token: "test-token",
                data: { event_type: event_type, payload: payload.merge(call_control_id: call.call_control_id) } }
  end

  def reminder_call(attempt_number)
    TelnyxCall.create!(occurrence: occurrence, user: senior, purpose: "reminder", attempt_number: attempt_number,
                       call_control_id: "rem-#{attempt_number}", status: "initiated", outcome: "pending",
                       to_number: senior.phone)
  end

  def escalation_to(caregiver) = occurrence.escalation_calls.find_by!(user: caregiver)

  describe "what starts it" do
    it "starts with the first caregiver when the last call to the care receiver goes unanswered" do
      call = reminder_call(TelnyxCall::MAX_ATTEMPTS)

      expect { telnyx_post(call, "call.hangup") }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 1)
    end

    it "waits while the care receiver still has calls to come" do
      call = reminder_call(1)

      expect { telnyx_post(call, "call.hangup") }.not_to have_enqueued_job(EscalationCallJob)
    end

    it "is only for reminders marked as time-critical" do
      reminder.update!(critical: false)
      call = reminder_call(TelnyxCall::MAX_ATTEMPTS)

      expect { telnyx_post(call, "call.hangup") }.not_to have_enqueued_job(EscalationCallJob)
    end

    # A 9 is an answer. The care receiver saying stop is not a reason to ring
    # somebody else about them.
    it "does not start when the care receiver pressed 9" do
      call = reminder_call(TelnyxCall::MAX_ATTEMPTS)
      call.update!(outcome: "opted_out", completed_at: Time.current)

      expect { telnyx_post(call, "call.hangup") }.not_to have_enqueued_job(EscalationCallJob)
    end
  end

  describe "ringing a caregiver" do
    it "rings the caregiver in that position" do
      EscalationCallJob.perform_now(occurrence.id, 1)

      call = escalation_to(first)
      expect(call.to_number).to eq(first.phone)
      expect(TelnyxVoiceService).to have_received(:escalate).with(call)
    end

    it "keeps escalation calls out of the care receiver's own calls" do
      EscalationCallJob.perform_now(occurrence.id, 1)

      expect(occurrence.telnyx_calls).to be_empty
      expect(occurrence.escalation_calls.count).to eq(1)
    end

    it "skips straight to the next person when this one has not agreed to these calls" do
      first.update_columns(escalation_consent_at: nil)

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
      expect(TelnyxVoiceService).not_to have_received(:escalate)
    end

    it "skips somebody who is no longer a caregiver" do
      first.update_columns(role: User.roles[:senior])

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
      expect(TelnyxVoiceService).not_to have_received(:escalate)
    end

    it "skips somebody who has said no on a call" do
      first.update_columns(escalation_opted_out_at: 1.hour.ago)

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
    end

    it "skips somebody outside their own calling hours" do
      first.update!(tz: "Asia/Tokyo") # 11pm there

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
      expect(TelnyxVoiceService).not_to have_received(:escalate)
    end

    it "skips somebody who has had the day's allowance of these calls" do
      TelnyxCall::MAX_ESCALATIONS_PER_DAY.times do |i|
        other = Occurrence.create!(reminder: reminder, scheduled_at: (i + 1).hours.ago, status: :pending)
        TelnyxCall.reserve_escalation(other, first, 1).update!(completed_at: Time.current, status: "completed")
      end

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
    end

    it "stops once the dose has been marked done" do
      occurrence.update!(status: :acknowledged)

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }.not_to have_enqueued_job(EscalationCallJob)
      expect(TelnyxVoiceService).not_to have_received(:escalate)
    end

    it "rings nobody after somebody has said they will check" do
      EscalationCallJob.perform_now(occurrence.id, 1)
      escalation_to(first).update!(outcome: "accepted", completed_at: Time.current)

      EscalationCallJob.perform_now(occurrence.id, 2)

      expect(TelnyxVoiceService).to have_received(:escalate).once
    end

    it "does not ring the same position twice when the job runs twice" do
      EscalationCallJob.perform_now(occurrence.id, 1)
      escalation_to(first).update!(completed_at: Time.current, status: "completed")

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }.not_to have_enqueued_job(EscalationCallJob)
      expect(TelnyxVoiceService).to have_received(:escalate).once
    end

    # Codex and Copilot on #211: a call whose ending never reached us held the
    # caregiver's number, and every later escalation skipped them.
    it "frees a caregiver's number held by an abandoned call" do
      stuck = Occurrence.create!(reminder: reminder, scheduled_at: 2.days.ago, status: :missed)
      TelnyxCall.reserve_escalation(stuck, first, 1, now: 2.days.ago).update_columns(created_at: 2.days.ago)

      EscalationCallJob.perform_now(occurrence.id, 1)

      expect(TelnyxVoiceService).to have_received(:escalate).with(escalation_to(first))
    end

    it "stops after the last position" do
      expect { EscalationCallJob.perform_now(occurrence.id, TelnyxCall::MAX_ESCALATION_POSITIONS + 1) }
        .not_to have_enqueued_job(EscalationCallJob)
      expect(TelnyxVoiceService).not_to have_received(:escalate)
    end

    it "tries the next person now when the call could not be placed" do
      allow(TelnyxVoiceService).to receive(:escalate).and_return(nil)

      expect { EscalationCallJob.perform_now(occurrence.id, 1) }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
    end

    context "while escalation calls are switched off" do
      let(:flags) { { phone_call_reminders: true, escalation_calls: false } }

      it "rings nobody" do
        EscalationCallJob.perform_now(occurrence.id, 1)

        expect(TelnyxVoiceService).not_to have_received(:escalate)
      end
    end
  end

  describe "the call" do
    let(:call) do
      EscalationCallJob.perform_now(occurrence.id, 1)
      escalation_to(first)
    end

    it "names the care receiver and the time, never the reminder" do
      said = nil
      allow(TelnyxVoiceService).to receive(:gather_digit) { |**kw| said = kw }

      telnyx_post(call, "call.answered")

      expect(said[:prompt]).to include("calling about Mom").and include("9:40 AM")
      expect(said[:prompt]).not_to include("Insulin")
      expect(said[:language]).to eq("en-US")
    end

    describe "pressing 1" do
      it "records that this caregiver will check, and rings nobody else" do
        expect { telnyx_post(call, "call.gather.ended", digits: "1") }.not_to have_enqueued_job(EscalationCallJob)

        expect(call.reload.outcome).to eq("accepted")
      end

      it "emails the other caregivers, and not the one who is checking" do
        expect { telnyx_post(call, "call.gather.ended", digits: "1") }
          .to have_enqueued_mail(ReminderActivityMailer, :escalation_accepted)
          .with(params: hash_including(caregiver: second, accepted_by: first), args: [])
          .exactly(:once)
      end

      it "does not mark the dose done, since a caregiver checking is not the dose" do
        telnyx_post(call, "call.gather.ended", digits: "1")

        expect(occurrence.reload).to be_status_pending
      end

      it "says who it will tell" do
        said = nil
        allow(TelnyxVoiceService).to receive(:speak) { |**kw| said = kw[:message]; { "data" => { "result" => "ok" } } }

        telnyx_post(call, "call.gather.ended", digits: "1")

        expect(said).to include("checking on Mom")
      end
    end

    it "passes to the next person straight away on 2" do
      expect { telnyx_post(call, "call.gather.ended", digits: "2") }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
      expect(call.reload.outcome).to eq("passed")
    end

    it "stops these calls to this caregiver on 9, and passes on" do
      expect { telnyx_post(call, "call.gather.ended", digits: "9") }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)

      expect(first.reload.escalation_opted_out_at).to be_present
      expect(senior.reload.call_opted_out_at).to be_nil
    end

    it "waits the gap before the next person when nothing is pressed" do
      expect { telnyx_post(call, "call.gather.ended", digits: "") }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
        .at(Time.current + TelnyxCall::ESCALATION_GAP)
    end

    it "waits the gap before the next person when it is not picked up" do
      expect { telnyx_post(call, "call.hangup") }
        .to have_enqueued_job(EscalationCallJob).with(occurrence.id, 2)
        .at(Time.current + TelnyxCall::ESCALATION_GAP)
    end

    # Copilot on #211: the keypress handled first, then a hangup that had read
    # the call as still pending. The hangup must not undo the 1.
    it "keeps a 1 when the hangup is handled from a stale read" do
      telnyx_post(call, "call.answered")
      stale = TelnyxCall.find(call.id)
      telnyx_post(call, "call.gather.ended", digits: "1")

      TelnyxWebhooksController.new.send(:handle_hangup, stale)

      expect(call.reload.outcome).to eq("accepted")
      expect(enqueued_jobs.select { |j| j["job_class"] == "EscalationCallJob" }).to be_empty
    end

    it "still counts a 1 delivered after the hangup" do
      telnyx_post(call, "call.answered")
      telnyx_post(call, "call.hangup")
      telnyx_post(call, "call.gather.ended", digits: "1", status: "call_hangup")

      expect(call.reload.outcome).to eq("accepted")
      perform_enqueued_jobs(only: EscalationCallJob)
      expect(TelnyxVoiceService).to have_received(:escalate).once
    end
  end

  describe "the order" do
    let(:manager) { first }

    def sign_in(user)
      post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
    end

    before { sign_in(manager) }

    it "is shown on the care receiver's page with each caregiver's standing" do
      second.update_columns(escalation_consent_at: nil)

      get "/dashboard/senior/#{senior.id}"

      panel = Nokogiri::HTML(response.body).at_css("#escalation-order")
      expect(panel.text).to include("Has confirmed").and include("Hasn't confirmed a number yet")
    end

    # A care receiver linked on the caregiver side (a role changed after the
    # link was made) can never confirm a number, so is not offered.
    it "lists only caregivers" do
      other = create(:user, :senior, name: "Johnny", tz: "America/New_York")
      CaregiverLink.create!(senior: senior, caregiver: other, permission: :manage)

      get "/dashboard/senior/#{senior.id}"

      panel = Nokogiri::HTML(response.body).at_css("#escalation-order")
      expect(panel.text).not_to include("Johnny")
    end

    it "swaps two caregivers" do
      first_link = CaregiverLink.find_by!(caregiver: first)
      second_link = CaregiverLink.find_by!(caregiver: second)

      patch "/dashboard/senior/#{senior.id}/escalation_order",
        params: { positions: { first_link.id => "2", second_link.id => "1" } }

      expect(first_link.reload.escalation_position).to eq(2)
      expect(second_link.reload.escalation_position).to eq(1)
      expect(flash[:notice]).to include("we'll call Navjeet, then Christy")
    end

    # Codex and Copilot on #211: saving an untouched order emptied it.
    it "keeps the order when it is saved unchanged" do
      first_link = CaregiverLink.find_by!(caregiver: first)
      second_link = CaregiverLink.find_by!(caregiver: second)

      patch "/dashboard/senior/#{senior.id}/escalation_order",
        params: { positions: { first_link.id => "1", second_link.id => "2" } }

      expect(first_link.reload.escalation_position).to eq(1)
      expect(second_link.reload.escalation_position).to eq(2)
    end

    # Copilot on #215: a caregiver whose role changed is hidden from the list
    # but kept their place, so giving that place to someone else failed.
    it "can give a former caregiver's place to someone else" do
      first.update_columns(role: User.roles[:senior])
      second_link = CaregiverLink.find_by!(caregiver: second)
      sign_in(second)

      patch "/dashboard/senior/#{senior.id}/escalation_order",
        params: { positions: { second_link.id => "1" } }

      expect(response).to redirect_to(%r{/dashboard/senior/#{senior.id}})
      expect(second_link.reload.escalation_position).to eq(1)
      expect(CaregiverLink.find_by!(caregiver: first).escalation_position).to be_nil
    end

    it "takes somebody off the list" do
      second_link = CaregiverLink.find_by!(caregiver: second)
      first_link = CaregiverLink.find_by!(caregiver: first)

      patch "/dashboard/senior/#{senior.id}/escalation_order",
        params: { positions: { first_link.id => "1", second_link.id => "" } }

      expect(second_link.reload.escalation_position).to be_nil
      expect(first_link.reload.escalation_position).to eq(1)
    end

    it "refuses two people in one place" do
      first_link = CaregiverLink.find_by!(caregiver: first)
      second_link = CaregiverLink.find_by!(caregiver: second)

      patch "/dashboard/senior/#{senior.id}/escalation_order",
        params: { positions: { first_link.id => "1", second_link.id => "1" } }

      expect(flash[:alert]).to include("only have one person")
      expect(second_link.reload.escalation_position).to eq(2)
    end

    it "tells a caregiver on their profile whose list they are on" do
      get "/profile"

      expect(Nokogiri::HTML(response.body).at_css("#escalation-phone").text.squish).to include("on the call list for Mom (1st)")
    end

    context "for a caregiver who can only view" do
      before { CaregiverLink.find_by!(caregiver: first).update!(permission: :view) }

      it "is refused" do
        patch "/dashboard/senior/#{senior.id}/escalation_order", params: { positions: {} }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "while escalation calls are switched off" do
      let(:flags) { { phone_call_reminders: true, escalation_calls: false } }

      it "is neither shown nor saved" do
        get "/dashboard/senior/#{senior.id}"
        expect(Nokogiri::HTML(response.body).at_css("#escalation-order")).to be_nil

        patch "/dashboard/senior/#{senior.id}/escalation_order", params: { positions: {} }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
