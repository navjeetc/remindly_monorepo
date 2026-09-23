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

  before { allow(TelnyxVoiceService).to receive(:hangup!) }

  it "ends a call whose farewell never reported finishing, and frees the number" do
    call = farewell_call

    described_class.perform_now(call.id)

    expect(TelnyxVoiceService).to have_received(:hangup!).with(hash_including(call_control_id: "v3:farewell"))
    expect(call.reload.completed_at).to be_present
    expect(TelnyxCall.call_in_flight?(senior, Time.current)).to be(false)
  end

  # The ordinary case: the event path already did its job.
  it "does nothing to a call that has already hung up" do
    call = farewell_call(status: "hangup", completed_at: 1.minute.ago)

    described_class.perform_now(call.id)

    expect(TelnyxVoiceService).not_to have_received(:hangup!)
  end

  # Freeing a number whose call may still be connected lets a second call be
  # dialled into it. An unconfirmed hangup is retried, and the claim stands in
  # the meantime -- held too long is recoverable, freed too early is not.
  it "keeps the number claimed, and retries, when the hangup cannot be confirmed" do
    allow(TelnyxVoiceService).to receive(:hangup!).and_raise(RuntimeError, "Telnyx hangup failed")
    call = farewell_call

    expect { described_class.perform_now(call.id) }
      .to have_enqueued_job(described_class).with(call.id)

    expect(call.reload.completed_at).to be_nil
  end

  # A crash between the farewell being accepted and the line being held leaves
  # the row stamped complete on a connected call. The number must read as taken
  # for as long as this job is still trying to end that call.
  it "re-claims the number before trying, so it stays taken while the hangup is retried" do
    allow(TelnyxVoiceService).to receive(:hangup!).and_raise(RuntimeError, "Telnyx hangup failed")
    call = farewell_call(completed_at: 1.minute.ago)

    described_class.perform_now(call.id)

    expect(call.reload.completed_at).to be_nil
    expect(TelnyxCall.call_in_flight?(senior, Time.current)).to be(true)
  end

  # A dropped connection is as unconfirmed as a refusal, and has to be retried
  # the same way rather than ending the job after one attempt.
  it "retries a network failure, not only a refusal" do
    allow(TelnyxVoiceService).to receive(:hangup!).and_raise(Errno::ECONNRESET)
    call = farewell_call

    expect { described_class.perform_now(call.id) }
      .to have_enqueued_job(described_class).with(call.id)

    expect(call.reload.completed_at).to be_nil
  end

  # completed_at is not evidence the call ended. When another row already held
  # the number's live claim, the farewell could not clear it, so a goodbye could
  # be playing on a row that still reads as complete.
  it "ends a farewell call even when its row reads as complete" do
    call = farewell_call(completed_at: 1.minute.ago)

    described_class.perform_now(call.id)

    expect(TelnyxVoiceService).to have_received(:hangup!).with(hash_including(call_control_id: "v3:farewell"))
  end

  it "does nothing for a call that no longer exists" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
