# frozen_string_literal: true

require "net/http"

# Mailing-list subscribers, mirrored into GoHighLevel as contacts so campaigns
# can be sent from there instead of from Rails (and off Postmark, whose
# reputation carries the magic sign-in links).
#
# The GHL sub-account is shared with Navjeet's other businesses: roughly 860
# phone leads for other work. The only thing that separates Remindly's
# contacts from those is their tags, so this class never touches a contact
# except through tags it owns (every one starts with "remindly-"), and never
# overwrites a field another business may have set.
#
# Two GHL behaviours shape it:
#
# * Tags passed to /contacts/upsert *replace* the contact's existing tags. A
#   subscriber who is already a lead elsewhere would lose that business's
#   tags, so tags go through the add/remove endpoints, which only append or
#   remove.
# * Upsert would equally overwrite `source`. So the contact is looked up
#   first, and upsert (carrying `source`) is only ever used to create one that
#   does not exist. Setting `source` in the same call that creates the contact
#   also means a retry cannot skip it: the first version set it in a second
#   call, and a retry after that call failed found an existing contact and
#   never set it at all.
#
# Dark until configured: with no token and location in credentials every
# call is a no-op, so this can ship before the GHL side exists.
#
#   go_high_level:
#     token: <Private Integration token, scopes contacts.write + contacts.readonly>
#     location_id: <sub-account id>
#     webhook_secret: <random string, also set in the GHL unsubscribe workflow>
class GoHighLevel
  BASE_URL = "https://services.leadconnectorhq.com"
  API_VERSION = "2021-07-28"
  TIMEOUT = 10

  SOURCE = "Remindly website"
  TAG_PREFIX = "remindly-"
  SUBSCRIBER_TAG = "remindly-subscriber"

  # Raised for a response GHL refused or a request that never completed; the
  # job retries on this one class.
  class Error < StandardError; end

  # Everything Net::HTTP raises when the connection, not GHL, is the problem.
  # Families rather than members: listing errno classes one by one let
  # Errno::ENETUNREACH (and every other OS error not on the list) through, and
  # each of those dropped a change for good. SystemCallError is every Errno;
  # IOError covers EOFError; Timeout::Error covers Net's own timeouts.
  #
  # The last three are Net::HTTP's protocol errors: a garbled status line or
  # header (a proxy cutting a response short will do it). Each descends
  # straight from StandardError, outside every family above, so a transient
  # bad response failed the change for good instead of retrying.
  TRANSPORT_ERRORS = [
    Timeout::Error, IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError,
    Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
  ].freeze

  def self.configured? = credentials[:token].present? && credentials[:location_id].present?

  # "post:what-to-check-on-daily" -> "remindly-source-post-what-to-check-on-daily"
  def self.source_tag(source)
    slug = source.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
    "remindly-source-#{slug.presence || 'unknown'}"
  end

  def self.subscribe(email:, source:)
    return unless configured?

    contact_id = find_contact_id(email) || create_contact(email)
    current_source = source_tag(source)

    # One source tag, matching the row. Someone who leaves and rejoins from
    # another page would otherwise carry both pages' tags.
    stale = fetch_contact(contact_id)["tags"].to_a.select { |tag| tag.start_with?("#{TAG_PREFIX}source-") } - [ current_source ]
    request(Net::HTTP::Delete, "/contacts/#{contact_id}/tags", tags: stale) if stale.any?

    # Contacts synced before double opt-in (0.21.0) also carry
    # remindly-unverified, so a campaign can leave them out. Nothing adds it
    # now: a contact reaches GHL only once its owner has confirmed the address.
    request(Net::HTTP::Post, "/contacts/#{contact_id}/tags", tags: [ SUBSCRIBER_TAG, current_source ])
    contact_id
  end

  # The privacy policy promises that a mailing-list address is deleted when
  # its owner asks to stop, so leaving removes Remindly from GHL entirely:
  #
  # * A contact that is only Remindly's (we created it, and every tag on it is
  #   ours) is deleted.
  # * A contact another business also has is that business's record, not
  #   Remindly's to delete. Only Remindly's tags come off it, which removes
  #   everything Remindly put there.
  #
  # Looks the contact up rather than upserting: leaving must never create one.
  # Email do-not-disturb is deliberately not set; in a shared account it would
  # stop every other business from emailing them too.
  def self.unsubscribe(email:)
    return unless configured?

    contact_id = find_contact_id(email)
    return unless contact_id

    contact = fetch_contact(contact_id)
    tags = Array(contact["tags"])
    ours = tags.select { |tag| tag.start_with?(TAG_PREFIX) }

    if contact["source"] == SOURCE && tags == ours
      request(Net::HTTP::Delete, "/contacts/#{contact_id}")
    elsif ours.any?
      request(Net::HTTP::Delete, "/contacts/#{contact_id}/tags", tags: ours)
    end
    contact_id
  end

  # GHL answers a lookup with {"contact": {...}} or {"contact": null}. Anything
  # else is a malformed answer, not "no such contact": reading it as absence
  # would skip an unsubscribe's removal for good, or create a contact that
  # already exists. So it raises, and the job retries.
  def self.find_contact_id(email)
    query = URI.encode_www_form(locationId: location_id, email: email)
    response = request(Net::HTTP::Get, "/contacts/search/duplicate?#{query}")
    raise Error, "GHL contact lookup answered without a contact field" unless response.key?("contact")

    contact = response["contact"]
    return nil if contact.nil?

    contact.is_a?(Hash) && contact["id"].present? ? contact["id"] : raise(Error, "GHL contact lookup answered a contact without an id")
  end

  def self.fetch_contact(contact_id)
    contact = request(Net::HTTP::Get, "/contacts/#{contact_id}")["contact"]
    contact.is_a?(Hash) ? contact : raise(Error, "GHL GET /contacts/#{contact_id} answered without a contact")
  end

  # Only for an address find_contact_id has just come back empty for, so
  # `source` here labels a new contact rather than overwriting anybody's.
  def self.create_contact(email)
    request(Net::HTTP::Post, "/contacts/upsert", locationId: location_id, email: email, source: SOURCE)
      .dig("contact", "id") or raise Error, "GHL upsert returned no contact id"
  end

  def self.request(verb, path, body = nil)
    uri = URI("#{BASE_URL}#{path}")
    request = verb.new(uri)
    request["Authorization"] = "Bearer #{credentials[:token]}"
    request["Version"] = API_VERSION
    request["Accept"] = "application/json"
    if body
      request["Content-Type"] = "application/json"
      request.body = body.to_json
    end

    label = "GHL #{verb.name.demodulize.upcase} #{uri.path}"
    begin
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true,
        open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
        http.request(request)
      end
    rescue *TRANSPORT_ERRORS => e
      raise Error, "#{label} failed: #{e.class}"
    end
    raise Error, "#{label} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    parse(response.body, label)
  end

  # A 2xx with a body that is not a JSON object is GHL misbehaving, not a
  # programming error, and it gets the same retries as any other failed call.
  # Left as JSON::ParserError (or a NoMethodError from calling dig on an array)
  # it fell outside GoHighLevel::Error and failed the job for good. The body is
  # left out of the message, as everywhere else here.
  def self.parse(body, label)
    return {} if body.blank?

    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : raise(Error, "#{label} answered with a JSON #{parsed.class.name.downcase}, not an object")
  rescue JSON::ParserError
    raise Error, "#{label} answered with malformed JSON"
  end

  def self.location_id = credentials[:location_id]

  # The shared secret GHL's unsubscribe workflow sends; see
  # CrmUnsubscribesController.
  def self.webhook_secret = credentials[:webhook_secret]

  def self.credentials = Rails.application.credentials.go_high_level || {}
end
