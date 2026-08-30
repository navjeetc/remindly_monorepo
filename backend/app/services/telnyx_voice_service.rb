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

  # Net::HTTP's defaults are tens of seconds, and reconciliation calls the
  # provider from inside reserve — which runs in a web request as well as a job.
  # A provider that accepts a connection and then stalls would hold a web worker
  # for the whole default, and enough concurrent requests during a degradation
  # would exhaust the pool. Short and explicit: a lookup that has not answered in
  # a few seconds is not going to.
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 5


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

      # attempt_id names the exact row, which is the only identifier here that
      # cannot become ambiguous: every other field is a description of the
      # attempt, and descriptions collide. The occurrence and attempt_number are
      # still sent so a call already ringing when this deploys still correlates
      # on the old terms.
      client_state: Base64.strict_encode64(
        { attempt_id: attempt.id, occurrence_id: occurrence.id, user_id: senior.id,
          attempt_number: attempt.attempt_number }.to_json
      ),
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
    # Releases the senior's daily slot too: nothing rang, so it should not cost
    # them a later reminder once whatever failed here recovers.
    attempt&.release_slot!(status: "failed", outcome: "error", completed_at: Time.current)
    nil
  end

  # Places the call that asks whether this number consents to be telephoned.
  #
  # Almost the same as dial, and deliberately not folded into it. The two differ
  # in what client_state carries -- a verification has no occurrence to name --
  # and in what the webhook does on answer, and collapsing them would mean a
  # boolean threaded through both, which is how the wrong branch eventually
  # speaks the wrong words to somebody.
  def self.verify(attempt)
    senior = attempt.user
    # The number recorded on the attempt, not the one on the user now. A
    # caregiver can edit users.phone between the attempt being claimed and this
    # POST, and dialling the new one would ring a number nobody set out to
    # verify — while consent! later compared the keypress against a value that
    # never got called.
    number = attempt.to_number.presence
    return record_failure(attempt) if number.blank?

    from = credentials[:from_number]
    connection_id = credentials[:connection_id]
    return record_failure(attempt) if from.blank? || connection_id.blank?

    payload = {
      connection_id: connection_id,
      to: number,
      from: from,

      # attempt_id, because the descriptive fields cannot separate these rows.
      # Verification attempt numbers restart per *destination*, so one senior
      # moving from number A to number B on the same call_day has an attempt 1
      # for each. If A's reservation never got its call_control_id written back,
      # B's callback matches both rows, update_all tries to give them the same
      # id, the unique index rolls the whole thing back -- and B is answered by
      # somebody who then hears nothing. call_day and attempt_number stay for
      # calls already in flight across a deploy.
      client_state: Base64.strict_encode64(
        { attempt_id: attempt.id, user_id: senior.id, attempt_number: attempt.attempt_number,
          call_day: attempt.call_day.to_s, purpose: "verification" }.to_json
      ),
      command_id: command_id_for("verify")
    }

    hook = webhook_url
    payload[:webhook_url] = hook if hook.present?

    response = post("/calls", payload, command_id: payload[:command_id])
    unless response&.key?("data")
      Rails.logger.error "Telnyx verification dial failed for user #{senior.id}: #{response.inspect}"
      return record_failure(attempt)
    end

    data = response["data"]
    attempt.update!(
      call_control_id: data["call_control_id"],
      call_leg_id: data["call_leg_id"],
      status: "initiated",
      outcome: "pending"
    )
    data["call_control_id"]
  rescue => e
    Rails.logger.error "Telnyx verification dial failed for user #{attempt.user_id}: #{e.message}"
    record_failure(attempt)
  end

  # Play the reminder message using TTS.
  # language is Telnyx's code for the accent the voice reads with, and it has to
  # arrive with text already written in that language — the two travel together
  # or a Spanish voice reads English words at somebody who may not speak either.
  # See User::SPOKEN_LANGUAGES. "female" is the basic service level, which is
  # the one mode where Telnyx honours `language` at all; it is ignored for a
  # Polly.* voice.
  def self.speak(call_control_id:, message:, language: "en-US", command_id: nil, call: nil)
    post(
      "/calls/#{call_control_id}/actions/speak",
      {
        payload: message,
        voice: "female",
        language: language,
        service: "tts"
      },
      command_id: command_id
    )
  rescue => e
    Rails.logger.error "Telnyx speak failed for call #{call_control_id}: #{e.message}"
  end

  # A person who has just picked up is usually saying "hello". We answer and
  # start talking over them within milliseconds, which is abrupt, and worse than
  # abrupt: they hear their own voice through the earpiece rather than the
  # instruction, and the window to press a key is running while they work out
  # what is happening. Reported from a live call as "the announcement came
  # almost instantly without me saying anything".
  #
  # The pause goes into the synthesised audio rather than into our own timing.
  # Delaying the command instead would mean holding a web request or waiting on
  # a queue, and a reminder call is a bad place to depend on how busy the
  # workers are.
  GREETING_PAUSE = "2s"

  def self.with_opening_pause(text)
    "<speak><break time=\"#{GREETING_PAUSE}\"/>#{CGI.escapeHTML(text)}</speak>"
  end

  # Speaks a prompt and collects a single DTMF digit in one action.
  #
  # Raises rather than swallowing, because the caller records the call as
  # handled once this returns. A silent failure here is the worst outcome the
  # feature has: the senior answers, hears nothing, and no retry ever comes.
  # See .speak for why language and prompt must be chosen together.
  def self.gather_digit(call_control_id:, prompt:, language: "en-US", command_id: nil, payload_type: "text")
    response = post(
      "/calls/#{call_control_id}/actions/gather_using_speak",
      {
        digits: 1,
        # Say it once. Telnyx re-speaks the prompt when no digit is collected,
        # and left to its default it tries several times — which on a live test
        # put two identical recordings on a voicemail, sixty-one seconds apart
        # against a ten-second timeout. A repeat only helps someone who fumbled
        # the first prompt, and costs an extra voicemail message every single
        # time nobody picks up, which is exactly what makes an automated caller
        # feel like a robocall.
        #
        # Answering-machine detection was the intended answer to this and was
        # abandoned: its verdict came back inverted on live calls, calling a
        # silent person a machine and a real mailbox a person. Nothing sensitive
        # is spoken before a keypress now, so a repeat would only ever repeat
        # the opening line -- still not worth it, for the same robocall reason.
        maximum_tries: 1,
        timeout_millis: 10000,
        inter_digit_timeout_millis: 5000,
        terminating_digit: "#",
        payload: prompt,
        payload_type: payload_type,
        voice: "female",
        language: language,
        service: "tts"
      },
      command_id: command_id
    )

    raise "Telnyx gather_using_speak failed for call #{call_control_id}" if response.nil?

    response
  end

  # Whether the provider still considers this call live.
  #
  # Returns nil when we cannot tell — the API is unreachable, or answered
  # something unexpected. The caller must treat that as "unknown" rather than
  # "ended": closing a claim on a failed lookup would free the line while
  # somebody was still talking on it.
  def self.alive?(call_control_id)
    response = get("/calls/#{call_control_id}")
    return nil unless response&.key?("data")

    # A missing is_alive is not a "no". Coercing it would turn an unexpected
    # payload — a field renamed, a partial response — into a confident "the call
    # has ended", and free the claim on a line somebody is still holding. Absent
    # means unknown, and unknown means wait.
    live = response.dig("data", "is_alive")
    return nil if live.nil?

    !!live
  rescue => e
    Rails.logger.warn "Telnyx call lookup failed for #{call_control_id}: #{e.message}"
    nil
  end

  def self.get(path)
    uri = URI("#{API_BASE}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{credentials[:api_key]}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }

    # 404 means the provider has no record of it, which for our purposes is the
    # same as ended — there is nothing left to hang up.
    return { "data" => { "is_alive" => false } } if response.is_a?(Net::HTTPNotFound)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # Hang up a call. Used after a digit is collected or the call is done.
  # Raises when the hangup does not land. The tolerant version below is right
  # where a hangup is tidying up after something else has already ended the
  # call, and wrong where it is the only thing that will end it: the screening
  # gather times out, nothing else is going to hang up, and a swallowed failure
  # means a 200 back to Telnyx, no redelivery, and a line left open recording
  # silence. That is the bug this whole path exists to avoid.
  def self.hangup!(call_control_id:, command_id: nil)
    response = post(
      "/calls/#{call_control_id}/actions/hangup",
      {},
      command_id: command_id
    )
    raise "Telnyx hangup failed for call #{call_control_id}" if response.nil?

    response
  end

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

  private_class_method :credentials, :setting, :command_id_for, :verify_signature, :record_failure, :get

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

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
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
