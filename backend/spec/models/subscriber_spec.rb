require "rails_helper"

RSpec.describe Subscriber do
  describe ".subscribe" do
    it "adds a new address" do
      subscriber = described_class.subscribe(email: "ann@example.com", source: "home")

      expect(subscriber).to be_persisted
      expect(subscriber.source).to eq("home")
    end

    it "normalises the address so the unique index means something" do
      expect(described_class.subscribe(email: "  Ann@Example.COM ").email).to eq("ann@example.com")
    end

    # Signing up twice is a normal thing to do — people forget. It has to be
    # indistinguishable from signing up once, rather than an error telling a
    # stranger that their address is already on a list.
    it "returns the existing record instead of an error on a repeat signup" do
      first = described_class.subscribe(email: "ann@example.com")
      second = described_class.subscribe(email: "ANN@example.com")

      expect(second).to eq(first)
      expect(second.errors).to be_empty
      expect(described_class.count).to eq(1)
    end

    it "reports an address that cannot work" do
      subscriber = described_class.subscribe(email: "not-an-email")

      expect(subscriber).not_to be_persisted
      expect(subscriber.errors[:email]).to be_present
    end

    # Both columns are written straight from an unauthenticated public form, and
    # the format check is happy with an address of any length — so the cheapest
    # possible request could bloat the table.
    it "refuses an absurdly long address" do
      subscriber = described_class.subscribe(email: "#{"a" * 300}@example.com")

      expect(subscriber).not_to be_persisted
      expect(subscriber.errors[:email]).to be_present
    end

    it "still accepts the longest address SMTP will actually carry" do
      local = "a" * (254 - "@example.com".length)

      expect(described_class.subscribe(email: "#{local}@example.com")).to be_persisted
    end

    it "refuses an oversized source, which only our own forms should set" do
      subscriber = described_class.subscribe(email: "ann@example.com", source: "x" * 200)

      expect(subscriber).not_to be_persisted
      expect(subscriber.errors[:source]).to be_present
    end

    # Two requests for the same address — a double-clicked button is enough —
    # can both pass the lookup and the uniqueness validation before either
    # commits, and then the database index rejects the second insert. The save
    # is stubbed to raise because that is precisely what the index does; what
    # matters is that the loser gets the existing record rather than a 500.
    context "when it loses a race to another signup" do
      it "treats the rejected insert as a successful signup" do
        existing = described_class.create!(email: "ann@example.com", source: "won-the-race")

        allow(described_class).to receive(:find_by).and_return(nil, existing)
        allow_any_instance_of(described_class).to receive(:save)
          .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

        result = nil
        expect { result = described_class.subscribe(email: "ann@example.com") }.not_to raise_error
        expect(result).to eq(existing)
      end
    end
  end
end
