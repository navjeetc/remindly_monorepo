require "rails_helper"

# The screen this replaces would have been a number field and a checkbox. The
# checkbox is the whole problem: it would let one person arrange automated calls
# to another who had never agreed. These specs exist to make sure no such control
# creeps back in.
RSpec.describe "Caregiver managing a senior's phone reminders", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # These specs place verification calls, which are now refused outside the
  # senior's calling window — so without a fixed clock they pass by day and fail
  # by night. Mid-morning in New York, which is inside every window here.
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

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

    # An unresolvable tz is one of the two ways within_calling_hours? says no,
    # so the refusal branch is exactly where a bad identifier arrives -- and
    # naming the clock there with in_time_zone raises on it. tz is validated, so
    # this needs update_column to reach; the point is that a row written around
    # the validation refuses the call rather than 500ing at the caregiver.
    it "refuses without raising when the senior's timezone does not resolve" do
      senior.update_column(:tz, "Neverwhere/Nowhere")

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(response).to redirect_to(senior_dashboard_path(senior))
      expect(flash[:alert]).to include("We only call between")
      expect(TelnyxVoiceService).not_to have_received(:verify)
    end
  end

  # The controller allows a verification call after an opt-out, because its
  # keypress is the only thing that can lift one. The screen has to offer it, or
  # that permission exists only for someone willing to craft a POST by hand --
  # and the stopped-state copy promises a route the UI would have closed.
  describe "asking again after an opt-out" do
    before do
      senior.update!(phone: "+15551234567")
      senior.update!(call_opted_out_at: 1.day.ago)
    end

    it "still offers the caregiver a way to ask" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("Call and ask Mom")
    end

    it "says plainly that asking cannot undo the opt-out" do
      get senior_dashboard_path(senior)

      expect(response.body).to include("it cannot undo that")
    end

    it "places the call when asked" do
      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(TelnyxVoiceService).to have_received(:verify).once
      expect(senior.reload.call_opted_out_at).to be_present
    end
  end

  # reserve_verification answers a missing number with the same nil it uses for
  # "a call is in progress" — so without this the caregiver is told to try again
  # in a moment for a condition that waiting cannot fix.
  describe "asking when no number is saved" do
    it "says what is actually wrong" do
      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(flash[:alert]).to include("no phone number saved")
      expect(TelnyxVoiceService).not_to have_received(:verify)
    end
  end

  # The clock the caregiver is deciding by is their own, and the product assumes
  # it is not the senior's. The refusal message names the local time too, but
  # only after the button is pressed and only when the guard fires -- which is
  # never, in the case that matters: a tz that resolves cleanly and is simply
  # wrong reads as permission. Showing it up front is what puts a wrong zone in
  # front of the one person able to recognise it.
  describe "the senior's clock on the caregiver's screen" do
    before { senior.update!(phone: "+15551234567") }

    it "shows the senior's local time, not the caregiver's" do
      senior.update!(tz: "Asia/Tokyo")

      get senior_dashboard_path(senior)

      # 10:00 in New York, fixed by the around hook, is 23:00 in Tokyo.
      expect(response.body).to include("11:00pm")
      expect(response.body).to include("for Mom")
    end

    it "says so when the senior's clock puts them outside calling hours" do
      senior.update!(tz: "Asia/Tokyo")

      get senior_dashboard_path(senior)

      expect(response.body).to include("won't ring yet")
    end

    it "says nothing about a clock it cannot read" do
      senior.update_column(:tz, "Neverwhere/Nowhere")

      get senior_dashboard_path(senior)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("for Mom.")
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
  # Reconciliation asks the provider whether an old call is still connected, and
  # may hang it up and ask again — three round trips with their own timeouts.
  # Fine in a job; not fine in a request a caregiver is waiting on.
  describe "when something is already holding the line" do
    before do
      senior.update!(phone: "+15551234567")
      TelnyxCall.reserve_verification(senior)
    end

    it "does not call the provider from inside the request" do
      allow(TelnyxVoiceService).to receive(:alive?)

      post "/dashboard/senior/#{senior.id}/verify_phone"

      expect(TelnyxVoiceService).not_to have_received(:alive?)
    end

    it "hands the clearing-up to a worker and says to try again" do
      expect {
        post "/dashboard/senior/#{senior.id}/verify_phone"
      }.to have_enqueued_job(ReconcileStaleCallsJob).with(senior.id)

      expect(flash[:alert]).to include("Try again in a moment")
    end
  end
end
