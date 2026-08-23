require "net/http"
require "json"
require "cgi"
require "securerandom"
require "base64"

# Wraps the Telnyx Call Control API. Uses Net::HTTP so the only API dependency is
# an API key, a connection ID, and a from-number stored in Rails credentials.
# Optional Ed25519 webhook signature verification uses the 'ed25519' gem.
#
# The call flow for a single reminder:
#   1. POST /v2/calls to dial the senior.
#   2. On call.answered, POST gather_using_speak to announce the reminder and
#      collect one DTMF digit in one step.
#   3. On gather.ended, record the digit and acknowledge the occurrence.
#   4. On hangup, if no digit, mark as no_response.
class TelnyxVoiceService
  API_BASE = URI("https://api.telnyx.com/v2").freeze

  # Initiate an outbound call for the given occurrence. Returns the call_control_id
  # from Telnyx so we can correlate webhooks.
  # `attempt` is a TelnyxCall already claimed by TelnyxCall.reserve. Requiring it
  # rather than creating one here is the point: the row has to exist before the
  # POST, so a concurrent run collides on the unique index instead of placing a
  # second call to the same person for the same dose.
  def self.dial(occurrence, attempt:)
    senior = attempt.user
    phone = senior&.phone
    return record_failure(attempt) if phone.blank?

    from = credentials[:from_number]
    connection_id = credentials[:connection_id]
    return record_failure(attempt) if from.blank? || connection_id.blank?

    payload = {
      connection_id: connection_id,
      to: phone,
      from: from,
      client_state: Base64.strict_encode64({ occurrence_id: occurrence.id, user_id: senior.id }.to_json),
      command_id: command_id_for("dial")
    }

    # Only sent when it resolves to something reachable; otherwise Telnyx falls
    # back to the connection's own webhook URL.
    hook = webhook_url
    payload[:webhook_url] = hook if hook.present?

    response = post("/calls", payload, command_id: payload[:command_id])
    unless response&.key?("data")
      Rails.logger.error "Telnyx dial response missing data: #{response.inspect}"
      return record_failure(attempt)
    end

    data = response["data"]
    call_control_id = data["call_control_id"]

    attempt.update!(
      call_control_id: call_control_id,
      call_leg_id: data["call_leg_id"],
      status: "initiated",
      outcome: "pending"
    )
    call_control_id
  rescue => e
    Rails.logger.error "Telnyx dial failed for occurrence #{occurrence.id}: #{e.message}"
    record_failure(attempt)
  end

  # A claimed attempt that never became a call is still an attempt: it is left
  # recorded and failed rather than deleted, so it counts against the cap and
  # holds the retry window open. Deleting it would let the scheduler re-claim
  # the same number immediately and dial in a tight loop against whatever is
  # broken.
  def self.record_failure(attempt)
    attempt&.update(status: "failed", outcome: "error", completed_at: Time.current)
    nil
  end

  # Play the reminder message using TTS.
  def self.speak(call_control_id:, message:, command_id: nil, call: nil)
    post(
      "/calls/#{call_control_id}/actions/speak",
      {
        payload: message,
        voice: "female",
        language: "en-US",
        service: "tts"
      },
      command_id: command_id
    )
  rescue => e
    Rails.logger.error "Telnyx speak failed for call #{call_control_id}: #{e.message}"
  end

  # Speaks a prompt and collects a single DTMF digit in one action.
  #
  # Raises rather than swallowing, because the caller records the call as
  # handled once this returns. A silent failure here is the worst outcome the
  # feature has: the senior answers, hears nothing, and no retry ever comes.
  def self.gather_digit(call_control_id:, prompt:, command_id: nil)
    response = post(
      "/calls/#{call_control_id}/actions/gather_using_speak",
      {
        digits: 1,
        timeout_millis: 10000,
        inter_digit_timeout_millis: 5000,
        terminating_digit: "#",
        payload: prompt,
        voice: "female",
        language: "en-US",
        service: "tts"
      },
      command_id: command_id
    )

    raise "Telnyx gather_using_speak failed for call #{call_control_id}" if response.nil?

    response
  end

  # Hang up a call. Used after a digit is collected or the call is done.
  def self.hangup(call_control_id:, command_id: nil)
    post(
      "/calls/#{call_control_id}/actions/hangup",
      {},
      command_id: command_id
    )
  rescue => e
    Rails.logger.error "Telnyx hangup failed for call #{call_control_id}: #{e.message}"
  end

  # Verify a Telnyx webhook. Two modes are supported:
  #   1. Ed25519 signature verification (production recommended).
  #   2. A shared token in the webhook URL query string (dev/testing fallback).
  #
  # The URL configured in Telnyx can include either/both. If a public key is
  # configured, signature verification is attempted first.
  def self.webhook_valid?(request)
    public_key = credentials[:webhook_public_key]
    return verify_signature(request, public_key) if public_key.present?

    token = credentials[:webhook_token]

    # Fail closed. A blank token used to mean "accept anything", which is not a
    # lenient default but an open door: an environment with no Telnyx
    # credentials configured -- production, at the time of writing -- would
    # accept any POST to /telnyx/webhooks and let it acknowledge a reminder.
    # An unconfigured integration must reject callbacks, not trust them.
    return false if token.blank?

    ActiveSupport::SecurityUtils.secure_compare(request.params["token"].to_s, token)
  end

  # `private` governs instance methods only — singleton methods defined with
  # `def self.` stay public regardless, so the keyword that used to sit here did
  # nothing at all. private_class_method actually closes them. webhook_url is
  # deliberately left public: resolving it is the one piece of this class worth
  # asserting on directly, and its spec does.
  def self.credentials
    {
      api_key: setting(:api_key, "TELNYX_API_KEY"),
      connection_id: setting(:connection_id, "TELNYX_CONNECTION_ID"),
      from_number: setting(:from_number, "TELNYX_FROM_NUMBER"),
      webhook_token: setting(:webhook_token, "TELNYX_WEBHOOK_TOKEN"),
      webhook_public_key: setting(:webhook_public_key, "TELNYX_WEBHOOK_PUBLIC_KEY")
    }
  end

  # Telnyx wants every one of these as a JSON string. connection_id is all
  # digits, so an unquoted value in credentials.yml decodes as an Integer and
  # to_json emits a bare number, which the API rejects as an invalid
  # connection_id -- a confusing error for a value that is in fact correct.
  def self.setting(key, env_var)
    value = Rails.application.credentials.dig(:telnyx, key) || ENV[env_var]
    value.presence && value.to_s
  end

  # Where Telnyx should send this call's events. Sent on the call itself, which
  # overrides the URL configured on the connection, so each environment routes
  # its own callbacks instead of one global setting in the portal being flipped
  # by hand between production and a tunnel. That setting has exactly one
  # failure mode and it is silent: the call connects, nothing is listening, and
  # the senior hears silence until it times out.
  #
  # Returns nil when the base is somewhere Telnyx cannot reach. Sending
  # http://localhost:5000 would guarantee no webhook ever arrives; omitting the
  # key falls back to whatever the connection has configured, which at least
  # stands a chance.
  UNREACHABLE_HOSTS = %w[localhost 127.0.0.1 0.0.0.0 ::1].freeze

  def self.webhook_url
    base = (Rails.application.credentials.base_url || ENV["APP_URL"]).to_s.strip
    return nil if base.empty?

    base = "https://#{base}" unless base.start_with?("http")
    base = base.chomp("/")

    host = begin
      URI.parse(base).host
    rescue URI::InvalidURIError
      nil
    end
    return nil if host.blank? || UNREACHABLE_HOSTS.include?(host)

    url = "#{base}/telnyx/webhooks"
    token = credentials[:webhook_token]
    token.present? ? "#{url}?token=#{CGI.escape(token)}" : url
  end

  def self.command_id_for(prefix)
    "#{prefix}-#{SecureRandom.uuid}"
  end

  def self.verify_signature(request, public_key_b64)
    signature_b64 = request.headers["HTTP_TELNYX_SIGNATURE_ED25519"]
    timestamp = request.headers["HTTP_TELNYX_TIMESTAMP"]

    return false if signature_b64.blank? || timestamp.blank?

    message = "#{timestamp}|#{request.raw_post}"
    verify_key = Ed25519::VerifyKey.new(Base64.decode64(public_key_b64))
    signature = Base64.decode64(signature_b64)

    verify_key.verify(signature, message)
  rescue Ed25519::VerifyError, ArgumentError => e
    Rails.logger.warn "Telnyx webhook signature verification failed: #{e.message}"
    false
  end

  private_class_method :credentials, :setting, :command_id_for, :verify_signature, :record_failure

  def self.post(path, body, command_id: nil)
    body[:command_id] = command_id if command_id.present?

    # API_BASE carries the /v2 prefix, so join rather than assigning uri.path --
    # assigning replaces the whole path and silently drops the version, which
    # the API answers with a 401 that reads like a bad API key.
    uri = URI("#{API_BASE}#{path}")

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{credentials[:api_key]}"
    request.body = body.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "Telnyx API error #{response.code} for #{path}: #{response.body&.first(500)}"
      return nil
    end

    JSON.parse(response.body)
  end

  private_class_method :post
end
