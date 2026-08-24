require "rails_helper"

# The URL Telnyx is told to call back on is the one setting whose failure is
# entirely silent: get it wrong and the call still connects, still rings, and
# the senior hears nothing until it times out. There is no error anywhere.
RSpec.describe TelnyxVoiceService do
  include ActiveSupport::Testing::TimeHelpers

  # These specs place verification calls, which are now refused outside the
  # senior's calling window — so without a fixed clock they pass by day and fail
  # by night. Mid-morning in New York, which is inside every window here.
  around { |example| travel_to(ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 10, 0)) { example.run } }

  describe ".webhook_url" do
    def with(base_url: nil, app_url: nil, token: "shhh")
      allow(Rails.application.credentials).to receive(:base_url).and_return(base_url)
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :webhook_token).and_return(token)

      previous = ENV["APP_URL"]
      app_url.nil? ? ENV.delete("APP_URL") : ENV["APP_URL"] = app_url
      begin
        described_class.webhook_url
      ensure
        previous.nil? ? ENV.delete("APP_URL") : ENV["APP_URL"] = previous
      end
    end

    it "adds https to a bare host, because credentials store one" do
      expect(with(base_url: "remindly.anakhsoft.com"))
        .to eq("https://remindly.anakhsoft.com/telnyx/webhooks?token=shhh")
    end

    it "takes APP_URL when no base_url is configured, which is how a tunnel is pointed at a dev box" do
      expect(with(app_url: "https://abc123.ngrok-free.dev"))
        .to eq("https://abc123.ngrok-free.dev/telnyx/webhooks?token=shhh")
    end

    it "prefers the credential over the environment" do
      expect(with(base_url: "remindly.anakhsoft.com", app_url: "https://abc123.ngrok-free.dev"))
        .to start_with("https://remindly.anakhsoft.com/")
    end

    it "escapes the token rather than letting it break the query string" do
      expect(with(base_url: "example.com", token: "a b&c=d")).to end_with("?token=a+b%26c%3Dd")
    end

    it "sends no URL at all for a loopback host" do
      expect(with(app_url: "http://localhost:5000")).to be_nil
      expect(with(app_url: "http://127.0.0.1:3000")).to be_nil
    end

    it "sends no URL when nothing is configured" do
      expect(with).to be_nil
    end

    it "does not double the slash when the base carries one" do
      expect(with(base_url: "https://example.com/")).to start_with("https://example.com/telnyx/webhooks")
    end
  end
  # A live test left two identical recordings on a voicemail sixty-one seconds
  # apart, against a ten-second timeout: Telnyx re-speaks the prompt when no
  # digit is collected, and its default is more than once.
  describe ".gather_digit" do
    it "asks Telnyx to speak the prompt exactly once" do
      sent = nil
      allow(described_class).to receive(:post) { |_path, body, **| sent = body; { "data" => {} } }

      described_class.gather_digit(call_control_id: "v3:abc", prompt: "time for your tablet")

      expect(sent[:maximum_tries]).to eq(1)
    end

    it "still raises when the provider refuses, so the event stays redeliverable" do
      allow(described_class).to receive(:post).and_return(nil)

      expect { described_class.gather_digit(call_control_id: "v3:abc", prompt: "x") }
        .to raise_error(/gather_using_speak failed/)
    end
  end
  describe ".verify" do
    let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551234567") }

    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :from_number).and_return("+15550000000")
      allow(Rails.application.credentials).to receive(:dig).with(:telnyx, :connection_id).and_return("conn-1")
    end

    # A caregiver can edit users.phone between the attempt being claimed and
    # this POST. Dialling the current value would ring a number nobody set out
    # to verify, and consent! would then compare the keypress against a number
    # that was never called.
    it "dials the number recorded on the attempt, not the one on the user now" do
      attempt = TelnyxCall.reserve_verification(senior)
      senior.update!(phone: "+15559998888")

      sent = nil
      allow(described_class).to receive(:post) { |_p, body, **| sent = body; { "data" => { "call_control_id" => "v3:x" } } }

      described_class.verify(attempt)

      expect(sent[:to]).to eq("+15551234567")
    end

    it "refuses to dial an attempt with no recorded number" do
      attempt = TelnyxCall.reserve_verification(senior)
      attempt.update_columns(to_number: nil)
      allow(described_class).to receive(:post)

      expect(described_class.verify(attempt)).to be_nil
      expect(attempt.reload.outcome).to eq("error")
    end
  end
end
