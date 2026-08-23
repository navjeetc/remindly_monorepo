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
  def self.dial(occurrence, call: nil)
    senior = occurrence.reminder.user
    phone = senior&.phone
    return nil if phone.blank?

    from = credentials[:from_number]
    connection_id = credentials[:connection_id]
    return nil if from.blank? || connection_id.blank?

    payload = {
      connection_id: connection_id,
      to: phone,
      from: from,
      client_state: Base64.strict_encode64({ occurrence_id: occurrence.id, user_id: senior.id }.to_json),
      command_id: command_id_for("dial")
    }

    response = post("/calls", payload, command_id: payload[:command_id])
    unless response&.key?("data")
      Rails.logger.error "Telnyx dial response missing data: #{response.inspect}"
      return nil
    end

    data = response["data"]
    call_control_id = data["call_control_id"]
    call_leg_id = data["call_leg_id"]

    call ||= TelnyxCall.find_or_initialize_by(occurrence: occurrence, user: senior)
    call.assign_attributes(
      call_control_id: call_control_id,
      call_leg_id: call_leg_id,
      status: "initiated",
      outcome: "pending"
    )
    call.save!
    call_control_id
  rescue => e
    Rails.logger.error "Telnyx dial failed for occurrence #{occurrence.id}: #{e.message}"
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
  def self.gather_digit(call_control_id:, prompt:, command_id: nil, call: nil)
    post(
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
  rescue => e
    Rails.logger.error "Telnyx gather_using_speak failed for call #{call_control_id}: #{e.message}"
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
    return true if token.blank?

    request.params["token"] == token
  end

  private

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

  def self.webhook_url
    base = Rails.application.credentials.base_url || ENV.fetch("APP_URL", "http://localhost:5000")
    base = "https://#{base}" unless base.start_with?("http")
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
end
