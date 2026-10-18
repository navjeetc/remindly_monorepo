require "rails_helper"

# The funnel a paid ad is judged by. Each example builds the furthest one
# account got and checks it is counted at every step it reached and none after.
RSpec.describe Activation do
  subject(:activation) { described_class.new(since: 30.days.ago.to_date) }

  def caregiver(source: nil, signed_in: true, **attrs)
    create(:user, :caregiver, signup_source: source, first_signed_in_at: (Time.current if signed_in), **attrs)
  end

  def connect(caregiver, state: :provisional)
    senior = User.create!(role: :senior, name: "Mum", tz: "America/New_York")
    CaregiverLink.create!(caregiver: caregiver, senior: senior, permission: :manage, state: state)
    senior
  end

  def remind(senior)
    Reminder.create!(user: senior, title: "Morning tablets", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz)
  end

  it "counts each account at every step it reached, and none after" do
    caregiver(signed_in: false)                       # asked for a link, never opened it
    caregiver                                         # signed in, did nothing
    connect(caregiver)                                # added someone
    remind(connect(caregiver))                        # wrote a reminder
    remind(connect(caregiver, state: :active))        # and they agreed

    expect(activation.totals).to eq(created: 5, signed_in: 4, added: 3, reminded: 2, agreed: 1)
  end

  it "groups by the tag the account was created from, most accounts first" do
    remind(connect(caregiver(source: "meta"), state: :active))
    caregiver(source: "meta", signed_in: false)
    caregiver

    expect(activation.by_source).to eq([
      [ "meta", { created: 2, signed_in: 1, added: 1, reminded: 1, agreed: 1 } ],
      [ Activation::UNTAGGED, { created: 1, signed_in: 1, added: 0, reminded: 0, agreed: 0 } ]
    ])
  end

  # A caregiver creates the people they remind, and those accounts have no
  # email. Counting them would make every setup look like two sign-ups.
  it "leaves out the care receivers a caregiver creates, and admins" do
    connect(caregiver)
    create(:user, :admin)

    expect(activation.totals[:created]).to eq(1)
  end

  it "leaves out accounts created before the period" do
    caregiver(created_at: 40.days.ago)

    expect(activation.totals[:created]).to eq(0)
  end
end
