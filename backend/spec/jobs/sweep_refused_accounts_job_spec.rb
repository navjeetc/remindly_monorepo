# frozen_string_literal: true

require "rails_helper"

# Everything that deletes a refused provisional account can fail, and every one
# of those failures is swallowed rather than retried -- right inside a telephone
# call, wrong as the last word on whether somebody's refusal was honoured.
RSpec.describe SweepRefusedAccountsJob, type: :job do
  let(:caregiver) { create(:user, :caregiver, name: "Jane", email: "kid@example.com") }

  def refused(opted_out_at:, state: :provisional)
    create(:user, :senior, name: "Mom", phone: "+15551234567").tap do |senior|
      senior.update_columns(call_opted_out_at: opted_out_at)
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: state)
    end
  end

  it "deletes an account whose refusal was never carried out" do
    senior = refused(opted_out_at: 2.hours.ago)

    described_class.perform_now

    expect(User.exists?(senior.id)).to be(false)
  end

  # A refusal still in progress is not a refusal that failed. The farewell may
  # still be speaking, and its own job is thirty seconds behind it.
  it "leaves a refusal that has only just happened" do
    senior = refused(opted_out_at: 1.minute.ago)

    described_class.perform_now

    expect(User.exists?(senior.id)).to be(true)
  end

  # Pressing 9 on an account already in use means "stop telephoning me", and
  # this job must not read it as anything else however long ago it was said.
  it "never touches an account that is active" do
    senior = refused(opted_out_at: 2.hours.ago, state: :active)

    described_class.perform_now

    expect(User.exists?(senior.id)).to be(true)
  end

  it "never sweeps an account that also has an active link" do
    senior = refused(opted_out_at: 2.hours.ago)
    other = create(:user, :caregiver, name: "Sam", email: "sam@example.com")
    CaregiverLink.create!(senior: senior, caregiver: other, permission: :manage, state: :active)

    described_class.perform_now

    expect(User.exists?(senior.id)).to be(true)
  end

  it "ignores a provisional account that has not refused anything" do
    senior = refused(opted_out_at: nil)

    described_class.perform_now

    expect(User.exists?(senior.id)).to be(true)
  end
end
