require "rails_helper"

RSpec.describe ReconcileStaleCallsJob do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York", phone: "+15551234567") }

  it "closes a claim the provider says has ended" do
    claim = TelnyxCall.reserve_verification(senior)
    claim.update_columns(created_at: TelnyxCall::IN_FLIGHT_WINDOW.ago - 1.minute)
    claim.update!(call_control_id: "v3:x")
    allow(TelnyxVoiceService).to receive(:alive?).and_return(false)

    described_class.new.perform(senior.id)

    expect(claim.reload.completed_at).to be_present
  end

  it "leaves a live one alone" do
    claim = TelnyxCall.reserve_verification(senior)
    claim.update_columns(created_at: TelnyxCall::IN_FLIGHT_WINDOW.ago - 1.minute)
    claim.update!(call_control_id: "v3:x")
    allow(TelnyxVoiceService).to receive(:alive?).and_return(true)
    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.new.perform(senior.id)

    expect(claim.reload.completed_at).to be_nil
  end

  it "does nothing for a user who has since been deleted" do
    expect { described_class.new.perform(0) }.not_to raise_error
  end

  it "does nothing for a user with no number" do
    senior.update!(phone: nil)

    expect { described_class.new.perform(senior.id) }.not_to raise_error
  end
end
