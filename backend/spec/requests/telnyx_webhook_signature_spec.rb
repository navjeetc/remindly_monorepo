# frozen_string_literal: true

require "rails_helper"
require "ed25519"

# The signature path is what the design document calls the production
# verification mode, and until now nothing exercised it: every other spec stubs
# webhook_public_key to nil, so verify_signature never ran. A regression in the
# header names, the signed-message format, or the base64 decoding would have
# passed CI and surfaced only once signature mode was switched on — at which
# point every callback would be rejected, silently, and no reminder call would
# ever be acknowledged.
RSpec.describe "Telnyx webhook signature verification", type: :request do
  let(:signing_key) { Ed25519::SigningKey.generate }
  let(:public_key) { Base64.strict_encode64(signing_key.verify_key.to_bytes) }
  let(:timestamp) { Time.current.to_i.to_s }
  let(:payload) { { data: { event_type: "call.answered", payload: { call_control_id: "v3:abc" } } }.to_json }

  def signature_for(body, at: timestamp, key: signing_key)
    Base64.strict_encode64(key.sign("#{at}|#{body}"))
  end

  def post_signed(body, signature:, at: timestamp, configured_key: public_key)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(configured_key)

    post "/telnyx/webhooks", params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_TELNYX_SIGNATURE_ED25519" => signature,
           "HTTP_TELNYX_TIMESTAMP" => at
         }
  end

  it "accepts a correctly signed webhook" do
    post_signed(payload, signature: signature_for(payload))

    expect(response).not_to have_http_status(:unauthorized)
  end

  it "rejects a body that was tampered with after signing" do
    signature = signature_for(payload)
    post_signed(payload.sub("call.answered", "call.hangup"), signature: signature)

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a signature made with the wrong key" do
    post_signed(payload, signature: signature_for(payload, key: Ed25519::SigningKey.generate))

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a signature replayed against a different timestamp" do
    signature = signature_for(payload, at: "1000000000")
    post_signed(payload, signature: signature, at: "2000000000")

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a request with no signature header" do
    post_signed(payload, signature: "")

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects rather than falling back to the shared token when a public key is configured" do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_public_key).and_return(public_key)
    allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return("test-token")

    post "/telnyx/webhooks?token=test-token", params: payload,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end
end
