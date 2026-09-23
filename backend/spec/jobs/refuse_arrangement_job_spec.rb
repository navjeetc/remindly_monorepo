# frozen_string_literal: true

require "rails_helper"

# Pressing 9 on a setup call refuses the whole arrangement when the account is
# provisional. That deletion used to happen inline, which took the call row out
# from under the farewell -- so it waits now, and the waiting is what these
# examples are about.
RSpec.describe RefuseArrangementJob, type: :job do
  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }
  let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567") }

  def provisional_link
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :provisional)
  end

  it "deletes an account that is still provisional" do
    provisional_link

    described_class.perform_now(senior.id)

    expect(User.exists?(senior.id)).to be(false)
  end

  # Somebody already using Remindly who presses 9 is saying "stop telephoning
  # me", not "delete my account" -- and the thirty-second wait is thirty seconds
  # in which a caregiver can activate the link.
  it "leaves an account that became active while it waited" do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active)

    described_class.perform_now(senior.id)

    expect(User.exists?(senior.id)).to be(true)
  end

  it "does nothing for an account already gone" do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end

  # The farewell is normally ended by call.speak.ended. If that event is lost,
  # the call can still be live when this fires -- and destroying the user takes
  # the row with it, leaving a line nothing can close.
  it "closes a call still open before deleting the account it belongs to" do
    provisional_link
    call = TelnyxCall.create!(call_control_id: "v3:still-live", user: senior, purpose: "verification",
                              to_number: senior.phone, status: "hangup", outcome: "opted_out")

    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.perform_now(senior.id)

    expect(TelnyxVoiceService).to have_received(:hangup).with(hash_including(call_control_id: "v3:still-live"))
    expect(User.exists?(senior.id)).to be(false)
    expect(TelnyxCall.exists?(call.id)).to be(false)
  end

  # opt_out! stamps completed_at and say_farewell clears it again for the length
  # of the goodbye. A process dying in that gap leaves a row claiming to be
  # finished while the line is still up -- and filtering on completed_at alone
  # would skip the one call that matters, then delete it with the user.
  it "closes a recent opted-out call even when it claims to be finished" do
    provisional_link
    TelnyxCall.create!(call_control_id: "v3:farewell-pending", user: senior, purpose: "verification",
                       to_number: senior.phone, status: "gathering", outcome: "opted_out",
                       completed_at: Time.current)

    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.perform_now(senior.id)

    expect(TelnyxVoiceService).to have_received(:hangup).with(hash_including(call_control_id: "v3:farewell-pending"))
  end

  # Not every finished call, though: an old one is a different call, and dialling
  # the provider about it buys nothing.
  it "leaves an old finished call alone" do
    provisional_link
    TelnyxCall.create!(call_control_id: "v3:ancient", user: senior, purpose: "verification",
                       to_number: senior.phone, status: "hangup", outcome: "opted_out",
                       created_at: 2.hours.ago, completed_at: 2.hours.ago)

    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.perform_now(senior.id)

    expect(TelnyxVoiceService).not_to have_received(:hangup)
  end

  # Any other open call on the account was placed after the refusal. The likeliest
  # is somebody on a fresh setup call pressing 1 to agree -- the one call this
  # job must never end.
  it "leaves a newer call alone even while it deletes the account" do
    provisional_link
    TelnyxCall.create!(call_control_id: "v3:refusal", user: senior, purpose: "verification",
                       to_number: senior.phone, status: "gathering", outcome: "opted_out")
    TelnyxCall.create!(call_control_id: "v3:newer", user: senior, purpose: "verification",
                       to_number: "+15559990000", status: "answered", outcome: "pending")

    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.perform_now(senior.id)

    expect(TelnyxVoiceService).to have_received(:hangup).with(hash_including(call_control_id: "v3:refusal"))
    expect(TelnyxVoiceService).not_to have_received(:hangup).with(hash_including(call_control_id: "v3:newer"))
  end

  # Ending somebody's reminder is not a side effect this job is entitled to. An
  # account that became active in the meantime may well be on a call, so nothing
  # is hung up until the deletion itself has been authorised.
  it "hangs up nothing when it decides to leave the account alone" do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active)
    TelnyxCall.create!(call_control_id: "v3:a-real-reminder", user: senior, purpose: "verification",
                       to_number: senior.phone, status: "answered", outcome: "pending")

    allow(TelnyxVoiceService).to receive(:hangup)

    described_class.perform_now(senior.id)

    expect(TelnyxVoiceService).not_to have_received(:hangup)
    expect(User.exists?(senior.id)).to be(true)
  end

  # A failure closing the line must not stop the refusal being honoured: the
  # calls are already off, and the account is what the keypress was about.
  it "deletes the account even when the hangup fails" do
    provisional_link
    TelnyxCall.create!(call_control_id: "v3:gone", user: senior, purpose: "verification",
                       to_number: senior.phone, status: "hangup", outcome: "opted_out")

    allow(TelnyxVoiceService).to receive(:hangup).and_return(nil)

    described_class.perform_now(senior.id)

    expect(User.exists?(senior.id)).to be(false)
  end
end
