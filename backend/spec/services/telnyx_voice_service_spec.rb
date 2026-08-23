require "rails_helper"

# The URL Telnyx is told to call back on is the one setting whose failure is
# entirely silent: get it wrong and the call still connects, still rings, and
# the senior hears nothing until it times out. There is no error anywhere.
RSpec.describe TelnyxVoiceService do
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
end
