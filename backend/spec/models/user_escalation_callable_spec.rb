require "rails_helper"

# A caregiver's agreement to be rung about missed reminders. Read as facts, the
# same way callable_by_phone? is, and never confused with it.
RSpec.describe User, "#escalation_callable?" do
  let(:caregiver) { create(:user, :caregiver, name: "Christy", phone: "+15715550142") }

  it "needs an agreement" do
    expect(caregiver).not_to be_escalation_callable

    caregiver.update_columns(escalation_consent_at: Time.current)
    expect(caregiver).to be_escalation_callable
  end

  it "is stopped by an opt-out" do
    caregiver.update_columns(escalation_consent_at: 1.day.ago, escalation_opted_out_at: Time.current)

    expect(caregiver).not_to be_escalation_callable
  end

  it "forgets the agreement when the number changes" do
    caregiver.update_columns(escalation_consent_at: 1.day.ago)

    caregiver.update!(phone: "+15715550199")

    expect(caregiver.escalation_consent_at).to be_nil
  end

  it "forgets it when the number is removed" do
    caregiver.update_columns(escalation_consent_at: 1.day.ago)

    caregiver.update!(phone: nil)

    expect(caregiver).not_to be_escalation_callable
    expect(caregiver.escalation_consent_at).to be_nil
  end

  it "keeps the opt-out across a number change, since stopping is theirs to say" do
    caregiver.update_columns(escalation_opted_out_at: 1.day.ago)

    caregiver.update!(phone: "+15715550199")

    expect(caregiver.escalation_opted_out_at).to be_present
  end
end
