require "rails_helper"

RSpec.describe PruneAnalyticsJob do
  def visit(started_at, ip: "203.0.113.1")
    Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                        ip: ip, started_at: started_at)
  end

  # Visits store an IP address and a user agent. Nothing removed them before this
  # job existed, so they accumulated indefinitely.
  it "removes visits older than the retention window" do
    old = visit(120.days.ago)
    recent = visit(10.days.ago, ip: "203.0.113.2")

    described_class.perform_now

    expect(Ahoy::Visit.exists?(old.id)).to be(false)
    expect(Ahoy::Visit.exists?(recent.id)).to be(true)
  end

  it "removes events older than the retention window" do
    old = Ahoy::Event.create!(name: "Login Success", time: 120.days.ago, visit: visit(120.days.ago))
    recent = Ahoy::Event.create!(name: "Login Success", time: 10.days.ago, visit: visit(10.days.ago))

    described_class.perform_now

    expect(Ahoy::Event.exists?(old.id)).to be(false)
    expect(Ahoy::Event.exists?(recent.id)).to be(true)
  end

  # An event carries its own timestamp, so a recent event attached to an expired
  # visit would survive a time-only sweep and point at a row that is gone.
  it "removes a recent event whose visit has expired" do
    expired = visit(120.days.ago)
    Ahoy::Event.create!(name: "Login Success", time: 1.day.ago, visit_id: expired.id)

    described_class.perform_now

    expect(Ahoy::Event.where(visit_id: expired.id)).to be_empty
  end

  # started_at and time are nullable. A row with no timestamp can never satisfy
  # "recent enough to keep", and would otherwise hold an IP address forever.
  it "removes an undated visit" do
    undated = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
                                  ip: "203.0.113.9", started_at: nil)

    described_class.perform_now

    expect(Ahoy::Visit.exists?(undated.id)).to be(false)
  end

  it "removes an undated event" do
    undated = Ahoy::Event.create!(name: "Login Success", time: nil, visit: visit(1.day.ago))

    described_class.perform_now

    expect(Ahoy::Event.exists?(undated.id)).to be(false)
  end

  it "reports what it removed" do
    visit(120.days.ago)

    expect(described_class.perform_now).to include(visits: 1)
  end
end
