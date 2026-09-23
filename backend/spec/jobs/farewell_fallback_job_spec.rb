# frozen_string_literal: true

require "rails_helper"

# call.speak.ended is the only thing that ends a call once it has said goodbye.
# A connection that does not deliver that event, a lost delivery, or a failed
# hangup would otherwise leave somebody listening to silence and the number
# claimed against every later call.
RSpec.describe FarewellFallbackJob, type: :job do
  let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567") }

  def farewell_call(**attrs)
    TelnyxCall.create!({ call_control_id: "v3:farewell", user: senior, purpose: "verification",
                         to_number: senior.phone, status: "speaking", outcome: "consented",
                         completed_at: nil }.merge(attrs))
  end

  before { allow(TelnyxVoiceService).to receive(:hangup) }

  it "ends a call whose farewell never reported finishing, and frees the number" do
    call = farewell_call

    described_class.perform_now(call.id)

    expect(TelnyxVoiceService).to have_received(:hangup).with(hash_including(call_control_id: "v3:farewell"))
    expect(call.reload.completed_at).to be_present
    expect(TelnyxCall.call_in_flight?(senior, Time.current)).to be(false)
  end

  # The ordinary case: the event path already did its job.
  it "does nothing to a call that has already hung up" do
    call = farewell_call(status: "hangup", completed_at: 1.minute.ago)

    described_class.perform_now(call.id)

    expect(TelnyxVoiceService).not_to have_received(:hangup)
  end

  # Releasing the number matters more than the provider's answer. A row left
  # claiming the line blocks this person's next reminder.
  it "frees the number even when the hangup is refused" do
    allow(TelnyxVoiceService).to receive(:hangup).and_return(nil)
    call = farewell_call

    described_class.perform_now(call.id)

    expect(call.reload.completed_at).to be_present
  end

  it "does nothing for a call that no longer exists" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
