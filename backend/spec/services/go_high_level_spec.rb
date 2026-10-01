# frozen_string_literal: true

require "rails_helper"

# The GHL sub-account is shared with other businesses, so what matters most
# here is what this class must *not* do: replace another business's tags,
# overwrite a lead's source, or create a contact for someone leaving the list.
RSpec.describe GoHighLevel do
  let(:calls) { [] }

  before do
    allow(described_class).to receive(:credentials).and_return({ token: "tok", location_id: "loc1" })
    allow(described_class).to receive(:request) do |verb, path, body = nil|
      calls << [ verb.name.demodulize.upcase, path, body ]
      responses.fetch([ verb.name.demodulize.upcase, path.split("?").first ], {})
    end
  end

  describe ".subscribe" do
    context "for an address GHL has never seen" do
      let(:responses) { { [ "POST", "/contacts/upsert" ] => { "new" => true, "contact" => { "id" => "c1" } } } }

      it "creates the contact, sets its source, and tags it" do
        described_class.subscribe(email: "ann@example.com", source: "home")

        expect(calls).to eq([
          [ "POST", "/contacts/upsert", { locationId: "loc1", email: "ann@example.com" } ],
          [ "PUT", "/contacts/c1", { source: "Remindly website" } ],
          [ "POST", "/contacts/c1/tags", { tags: %w[remindly-subscriber remindly-source-home remindly-unverified] } ],
          [ "DELETE", "/contacts/c1/tags", { tags: %w[remindly-unsubscribed] } ]
        ])
      end
    end

    context "for someone already in GHL as another business's lead" do
      let(:responses) { { [ "POST", "/contacts/upsert" ] => { "new" => false, "contact" => { "id" => "c9" } } } }

      it "adds Remindly's tags without touching their source or passing tags to upsert" do
        described_class.subscribe(email: "lead@example.com", source: "post:daily-checks")

        upsert = calls.find { |_, path, _| path == "/contacts/upsert" }
        expect(upsert.last.keys).to contain_exactly(:locationId, :email)
        expect(calls.map(&:first)).not_to include("PUT")
        expect(calls).to include([ "POST", "/contacts/c9/tags", { tags: %w[remindly-subscriber remindly-source-post-daily-checks remindly-unverified] } ])
      end
    end

    context "when GHL answers without a contact id" do
      let(:responses) { { [ "POST", "/contacts/upsert" ] => {} } }

      it "raises, so the job retries instead of silently dropping the signup" do
        expect { described_class.subscribe(email: "ann@example.com", source: "home") }.to raise_error(GoHighLevel::Error)
      end
    end
  end

  describe ".unsubscribe" do
    context "when the contact exists" do
      let(:responses) { { [ "GET", "/contacts/search/duplicate" ] => { "contact" => { "id" => "c1" } } } }

      it "swaps the subscriber tag for the unsubscribed one" do
        described_class.unsubscribe(email: "ann@example.com")

        expect(calls).to eq([
          [ "GET", "/contacts/search/duplicate?locationId=loc1&email=ann%40example.com", nil ],
          [ "DELETE", "/contacts/c1/tags", { tags: %w[remindly-subscriber] } ],
          [ "POST", "/contacts/c1/tags", { tags: %w[remindly-unsubscribed] } ]
        ])
      end
    end

    context "when GHL has no such contact" do
      let(:responses) { { [ "GET", "/contacts/search/duplicate" ] => { "contact" => nil } } }

      it "stops there, and never creates a contact for someone leaving" do
        described_class.unsubscribe(email: "gone@example.com")

        expect(calls.map { |verb, path, _| [ verb, path.split("?").first ] }).to eq([ [ "GET", "/contacts/search/duplicate" ] ])
      end
    end
  end

  context "without credentials" do
    let(:responses) { {} }

    before { allow(described_class).to receive(:credentials).and_return({}) }

    it "does nothing at all" do
      described_class.subscribe(email: "ann@example.com", source: "home")
      described_class.unsubscribe(email: "ann@example.com")

      expect(calls).to be_empty
    end
  end

  describe ".source_tag" do
    let(:responses) { {} }

    it "turns a source into a tag GHL can filter on" do
      expect(described_class.source_tag("home")).to eq("remindly-source-home")
      expect(described_class.source_tag("post:What_To-Check")).to eq("remindly-source-post-what-to-check")
      expect(described_class.source_tag(nil)).to eq("remindly-source-unknown")
    end
  end

  describe ".request" do
    let(:responses) { {} }
    let(:sent) { [] }

    before do
      allow(described_class).to receive(:request).and_call_original
      allow(Net::HTTP).to receive(:start) do |*_, **_, &block|
        http = double("http")
        allow(http).to receive(:request) { |req| sent << req; reply }
        block.call(http)
      end
    end

    context "when GHL accepts" do
      let(:reply) { Net::HTTPOK.new("1.1", "200", "OK").tap { |r| allow(r).to receive(:body).and_return('{"contact":{"id":"c1"}}') } }

      it "sends the token, the API version and a JSON body" do
        result = described_class.request(Net::HTTP::Post, "/contacts/upsert", email: "ann@example.com")

        expect(result).to eq("contact" => { "id" => "c1" })
        expect(sent.first["Authorization"]).to eq("Bearer tok")
        expect(sent.first["Version"]).to eq("2021-07-28")
        expect(JSON.parse(sent.first.body)).to eq("email" => "ann@example.com")
      end
    end

    context "when GHL refuses" do
      let(:reply) { Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized").tap { |r| allow(r).to receive(:body).and_return("{}") } }

      it "raises without putting the address in the message" do
        expect { described_class.request(Net::HTTP::Get, "/contacts/search/duplicate?email=ann%40example.com") }
          .to raise_error(GoHighLevel::Error, "GHL GET /contacts/search/duplicate answered 401")
      end
    end
  end
end
