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
      let(:responses) do
        { [ "GET", "/contacts/search/duplicate" ] => { "contact" => nil },
          [ "POST", "/contacts/upsert" ] => { "new" => true, "contact" => { "id" => "c1" } },
          [ "GET", "/contacts/c1" ] => { "contact" => { "id" => "c1", "tags" => [] } } }
      end

      it "creates the contact with its source in one call, then tags it" do
        described_class.subscribe(email: "ann@example.com", source: "home")

        expect(calls).to eq([
          [ "GET", "/contacts/search/duplicate?locationId=loc1&email=ann%40example.com", nil ],
          [ "POST", "/contacts/upsert", { locationId: "loc1", email: "ann@example.com", source: "Remindly website" } ],
          [ "GET", "/contacts/c1", nil ],
          [ "POST", "/contacts/c1/tags", { tags: %w[remindly-subscriber remindly-source-home] } ]
        ])
      end
    end

    # Covers both an address that is already another business's lead and a
    # retry after the contact was created but tagging failed: either way the
    # contact exists, and only the tags may change.
    context "for a contact GHL already has" do
      let(:responses) do
        { [ "GET", "/contacts/search/duplicate" ] => { "contact" => { "id" => "c9" } },
          [ "GET", "/contacts/c9" ] => { "contact" => { "id" => "c9", "tags" => %w[lawn-care-lead] } } }
      end

      it "only adds Remindly's tags: no upsert, so no field and no tag of theirs is replaced" do
        described_class.subscribe(email: "lead@example.com", source: "post:daily-checks")

        expect(calls.map { |verb, path, _| [ verb, path.split("?").first ] }).to eq([
          [ "GET", "/contacts/search/duplicate" ],
          [ "GET", "/contacts/c9" ],
          [ "POST", "/contacts/c9/tags" ]
        ])
        expect(calls).to include([ "POST", "/contacts/c9/tags", { tags: %w[remindly-subscriber remindly-source-post-daily-checks] } ])
      end
    end

    context "for someone who rejoined from a different page" do
      let(:responses) do
        { [ "GET", "/contacts/search/duplicate" ] => { "contact" => { "id" => "c1" } },
          [ "GET", "/contacts/c1" ] => { "contact" => { "id" => "c1",
            "tags" => %w[remindly-subscriber remindly-source-home remindly-unverified lawn-care-lead] } } }
      end

      it "swaps the old page's source tag for the new one, touching nothing else" do
        described_class.subscribe(email: "ann@example.com", source: "routine_sheet")

        # remindly-unverified (from before double opt-in) is neither added nor
        # removed: a re-sync must not quietly mark old contacts as confirmed.
        expect(calls).to include([ "DELETE", "/contacts/c1/tags", { tags: %w[remindly-source-home] } ])
        expect(calls.last).to eq([ "POST", "/contacts/c1/tags", { tags: %w[remindly-subscriber remindly-source-routine-sheet] } ])
      end
    end

    context "when GHL creates the contact but returns no id" do
      let(:responses) do
        { [ "GET", "/contacts/search/duplicate" ] => { "contact" => nil }, [ "POST", "/contacts/upsert" ] => {} }
      end

      it "raises, so the job retries instead of silently dropping the signup" do
        expect { described_class.subscribe(email: "ann@example.com", source: "home") }.to raise_error(GoHighLevel::Error)
      end
    end

    # A malformed lookup used to read as "not found", and subscribe then
    # created a contact that may already exist.
    context "when the lookup answers without a contact field" do
      let(:responses) { { [ "GET", "/contacts/search/duplicate" ] => { "message" => "ok" } } }

      it "raises instead of creating a contact" do
        expect { described_class.subscribe(email: "ann@example.com", source: "home") }
          .to raise_error(GoHighLevel::Error, "GHL contact lookup answered without a contact field")
        expect(calls.map(&:second)).not_to include("/contacts/upsert")
      end
    end
  end

  # The privacy policy promises the address is deleted when someone asks to
  # stop. In a shared account that means deleting what is Remindly's and
  # nothing that belongs to another business.
  describe ".unsubscribe" do
    let(:found) { { [ "GET", "/contacts/search/duplicate" ] => { "contact" => { "id" => "c1" } } } }

    context "when the contact is only Remindly's" do
      let(:responses) do
        found.merge([ "GET", "/contacts/c1" ] => { "contact" => { "id" => "c1", "source" => "Remindly website",
          "tags" => %w[remindly-subscriber remindly-source-home remindly-unverified] } })
      end

      it "deletes it from GHL" do
        described_class.unsubscribe(email: "ann@example.com")

        expect(calls.last).to eq([ "DELETE", "/contacts/c1", nil ])
      end
    end

    context "when another business also has the contact" do
      let(:responses) do
        found.merge([ "GET", "/contacts/c1" ] => { "contact" => { "id" => "c1", "source" => "Remindly website",
          "tags" => %w[remindly-subscriber remindly-source-home lawn-care-lead] } })
      end

      it "removes only Remindly's tags and leaves their record alone" do
        described_class.unsubscribe(email: "ann@example.com")

        expect(calls.last).to eq([ "DELETE", "/contacts/c1/tags", { tags: %w[remindly-subscriber remindly-source-home] } ])
        expect(calls).not_to include([ "DELETE", "/contacts/c1", nil ])
      end
    end

    context "when another business created the contact, even with only Remindly's tags on it" do
      let(:responses) do
        found.merge([ "GET", "/contacts/c1" ] => { "contact" => { "id" => "c1", "source" => "Facebook ad",
          "tags" => %w[remindly-subscriber] } })
      end

      it "does not delete their contact" do
        described_class.unsubscribe(email: "ann@example.com")

        expect(calls.last).to eq([ "DELETE", "/contacts/c1/tags", { tags: %w[remindly-subscriber] } ])
      end
    end

    context "when the lookup answers a contact without an id" do
      let(:responses) { { [ "GET", "/contacts/search/duplicate" ] => { "contact" => { "email" => "ann@example.com" } } } }

      it "raises, so the removal is retried rather than skipped for good" do
        expect { described_class.unsubscribe(email: "ann@example.com") }
          .to raise_error(GoHighLevel::Error, "GHL contact lookup answered a contact without an id")
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

    [ Net::OpenTimeout, Net::WriteTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::ENETUNREACH, EOFError, OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError ].each do |failure|
      context "when the connection fails with #{failure}" do
        let(:reply) { nil }

        before { allow(Net::HTTP).to receive(:start).and_raise(failure) }

        it "raises GoHighLevel::Error, the one class the job retries" do
          expect { described_class.request(Net::HTTP::Post, "/contacts/upsert", email: "ann@example.com") }
            .to raise_error(GoHighLevel::Error, "GHL POST /contacts/upsert failed: #{failure}")
        end
      end
    end

    context "when GHL answers 200 with malformed JSON" do
      let(:reply) { Net::HTTPOK.new("1.1", "200", "OK").tap { |r| allow(r).to receive(:body).and_return('{"contact": {"id": "c1", "email": "ann@exa') } }

      it "raises GoHighLevel::Error, without the body, so the job retries" do
        expect { described_class.request(Net::HTTP::Get, "/contacts/c1") }
          .to raise_error(GoHighLevel::Error, "GHL GET /contacts/c1 answered with malformed JSON")
      end
    end

    context "when GHL answers 200 with JSON that is not an object" do
      let(:reply) { Net::HTTPOK.new("1.1", "200", "OK").tap { |r| allow(r).to receive(:body).and_return('["c1"]') } }

      it "raises GoHighLevel::Error rather than failing later on dig" do
        expect { described_class.request(Net::HTTP::Get, "/contacts/c1") }
          .to raise_error(GoHighLevel::Error, "GHL GET /contacts/c1 answered with a JSON array, not an object")
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
