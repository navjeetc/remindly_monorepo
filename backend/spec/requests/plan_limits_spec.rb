require "rails_helper"

# The plan limits where a caregiver meets them. During the beta none of these
# refuse anything, which the first example pins; the rest run as though paid
# plans had started.
RSpec.describe "Plan limits on the dashboard", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  let(:caregiver) { User.create!(email: "cg@example.com", role: :caregiver, name: "Care", tz: "America/New_York") }
  let(:senior) do
    User.create!(name: "Rose", role: :senior, tz: "America/New_York", email_undeliverable_at: Time.current)
  end

  before do
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage, state: :active)
    sign_in(caregiver)
  end

  def create_reminder(phone_call: "1")
    post "/dashboard/senior/#{senior.id}/reminder",
         params: { reminder: { title: "Take meds", time: "09:00", frequency: "daily", category: "medication",
                               critical: "0", phone_call: phone_call } }
  end

  it "refuses nothing during the beta" do
    expect {
      post "/dashboard/care_receiver", params: { user: { name: "Second", tz: "America/New_York" } }
    }.to change(User, :count).by(1)
    expect { 4.times { create_reminder } }.to change(senior.reminders, :count).by(4)
  end

  it "saves a reminder that shows on the screen only" do
    create_reminder(phone_call: "0")
    expect(senior.reminders.last.phone_call).to be(false)
  end

  describe "once paid plans have started" do
    before { stub_const("Plan::LAUNCHED_ON", Date.current - 1) }

    it "refuses a second parent on the free plan" do
      expect {
        post "/dashboard/care_receiver", params: { user: { name: "Second", tz: "America/New_York" } }
      }.not_to change(User, :count)
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to include("Free plan", "1 parent")
    end

    it "offers the screen when a fourth phone reminder is refused" do
      3.times { create_reminder }
      expect { create_reminder }.not_to change(senior.reminders, :count)
      expect(response.body).to include("Ring their phone")

      expect { create_reminder(phone_call: "0") }.to change(senior.reminders, :count).by(1)
    end

    it "refuses a third caregiver on the free plan" do
      CaregiverLink.create!(senior: senior, permission: :manage,
                            caregiver: User.create!(email: "two@example.com", role: :caregiver, name: "Two"))

      expect {
        post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: "three@example.com" }
      }.not_to change(CaregiverLink, :count)
      expect(flash[:alert]).to include("2 caregivers")
    end

    it "refuses a pairing token that would be a second parent" do
      self_signed = User.create!(email: "ann@example.com", role: :senior, name: "Ann")
      link = CaregiverLink.generate_pairing_token(senior: self_signed)

      post "/dashboard/pair", params: { token: link.pairing_token }

      expect(link.reload.caregiver_id).to be_nil
      expect(flash[:alert]).to include("1 parent")
    end

    it "keeps escalation calls for Family" do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
      allow(FeatureFlag).to receive(:enabled?).with(:escalation_calls).and_return(true)
      link = senior.senior_links.first

      patch "/dashboard/senior/#{senior.id}/escalation_order", params: { positions: { link.id.to_s => "1" } }

      expect(link.reload.escalation_position).to be_nil
      expect(flash[:alert]).to include("Family plan")
    end
  end
end
