require "rails_helper"

# The screen this replaces would have been a number field and a checkbox. The
# checkbox is the whole problem: it would let one person arrange automated calls
# to another who had never agreed. These specs exist to make sure no such control
# creeps back in.
RSpec.describe "Caregiver managing a senior's phone reminders", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  # Mirrors how the dashboard establishes a session after a magic-link verify,
  # the same way the acknowledgements specs do.
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  before do
    allow(TelnyxVoiceService).to receive(:verify).and_return("v3:placed")
    sign_in(caregiver)
  end

  describe "proposing a number" do
    it "saves it" do
      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "+15551234567" } }

      expect(senior.reload.phone).to eq("+15551234567")
    end

    it "does not thereby allow a single call" do
      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "+15551234567" } }

      expect(senior.reload.callable_by_phone?).to be false
      expect(senior.call_consent_at).to be_nil
    end

    it "rejects a number that is not dialable, without a 500" do
      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "not a number" } }

      expect(response).to redirect_to(senior_dashboard_path(senior))
      expect(senior.reload.phone).to be_nil
    end

    # The callback under this is the one the whole design rests on.
    it "revokes consent when the number is changed" do
      senior.update!(phone: "+15551234567")
      senior.update!(phone_verified_at: Time.current, call_consent_at: Time.current, call_reminders_enabled: true)

      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "+15559998888" } }

      expect(senior.reload.callable_by_phone?).to be false
    end
  end

  describe "asking the senior" do
    before { senior.update!(phone: "+15551234567") }

    it "places one call and grants nothing" do
      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(TelnyxVoiceService).to have_received(:verify).once
      expect(senior.reload.callable_by_phone?).to be false
    end

    # Refusing here made re-consent unreachable: this call is the only thing
    # whose keypress can lift an opt-out, so blocking it would have made the
    # promise "only they can change this, by agreeing on a call" impossible to
    # keep. Asking again is allowed; the bound and the visible count are the
    # safeguard.
    it "may still ask someone who previously said stop" do
      senior.update!(call_opted_out_at: 1.day.ago)

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(TelnyxVoiceService).to have_received(:verify).once
    end

    it "grants nothing by asking — the opt-out stands until they say otherwise" do
      senior.update!(call_opted_out_at: 1.day.ago)

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(senior.reload.call_opted_out_at).to be_present
      expect(senior.callable_by_phone?).to be false
    end

    it "stops after the day's allowance" do
      TelnyxCall::MAX_VERIFICATIONS_PER_DAY.times do
        TelnyxCall.reserve_verification(senior).update!(completed_at: Time.current)
      end

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(TelnyxVoiceService).not_to have_received(:verify)
    end
  end

  describe "a view-only caregiver" do
    let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :view) }

    it "cannot propose a number" do
      patch "/dashboard/senior/#{senior.id}/phone", params: { user: { phone: "+15551234567" } }

      expect(response).to have_http_status(:forbidden)
      expect(senior.reload.phone).to be_nil
    end

    it "cannot make the phone ring" do
      senior.update!(phone: "+15551234567")

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(response).to have_http_status(:forbidden)
      expect(TelnyxVoiceService).not_to have_received(:verify)
    end
  end

  it "refuses a caregiver who is not linked to this senior" do
    stranger = create(:user, :senior, name: "Someone else")

    patch "/dashboard/senior/#{stranger.id}/phone", params: { user: { phone: "+15551234567" } }

    expect(response).to have_http_status(:not_found)
    expect(stranger.reload.phone).to be_nil
  end

  it "refuses to make a stranger's phone ring" do
    stranger = create(:user, :senior, name: "Someone else", phone: "+15551234567")

    post "/dashboard/senior/#{stranger.id}/verify_phone"

    expect(response).to have_http_status(:not_found)
    expect(TelnyxVoiceService).not_to have_received(:verify)
  end
  # verify returns nil when the provider refuses, having marked the attempt
  # failed. Reporting success anyway leaves a caregiver waiting for a call that
  # was never placed — and waiting is the one state they cannot debug.
  describe "when the provider refuses the call" do
    before { senior.update!(phone: "+15551234567") }

    it "says so rather than claiming the phone is ringing" do
      allow(TelnyxVoiceService).to receive(:verify).and_return(nil)

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to include("Couldn't place the call")
    end

    it "reports success when the call was placed" do
      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(flash[:notice]).to include("Calling +15551234567")
    end
  end

  # The number can be edited between the attempt being claimed and the POST.
  # Dialling the current value would ring a number nobody set out to verify.
  it "dials the number recorded on the attempt, not whatever is on file now" do
    senior.update!(phone: "+15551234567")
    dialled = nil
    allow(TelnyxVoiceService).to receive(:verify) { |attempt| dialled = attempt.to_number; "v3:placed" }

    post "/dashboard/senior/#{senior.id}/verify_phone"

    expect(dialled).to eq("+15551234567")
  end
end
