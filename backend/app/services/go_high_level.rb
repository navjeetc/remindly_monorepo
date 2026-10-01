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
# * Upsert would equally overwrite `source`, so it is set only on a contact
#   GHL reports as new.
#
# Dark until configured: with no token and location in credentials every
# call is a no-op, so this can ship before the GHL side exists.
#
#   go_high_level:
#     token: <Private Integration token, scopes contacts.write + contacts.readonly>
#     location_id: <sub-account id>
class GoHighLevel
  BASE_URL = "https://services.leadconnectorhq.com"
  API_VERSION = "2021-07-28"
  TIMEOUT = 10

  SOURCE = "Remindly website"
  SUBSCRIBER_TAG = "remindly-subscriber"
  UNSUBSCRIBED_TAG = "remindly-unsubscribed"
  # Sign-ups are single opt-in, and a run of them in September 2026 looked like
  # subscription bombing (real addresses entered by bots). Every new contact
  # carries this until someone has confirmed they are real, so a campaign can
  # exclude it.
  UNVERIFIED_TAG = "remindly-unverified"

  # Raised for a response GHL refused; the job retries on it.
  class Error < StandardError; end

  def self.configured? = credentials[:token].present? && credentials[:location_id].present?

  # "post:what-to-check-on-daily" -> "remindly-source-post-what-to-check-on-daily"
  def self.source_tag(source)
    slug = source.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
    "remindly-source-#{slug.presence || 'unknown'}"
  end

  def self.subscribe(email:, source:)
    return unless configured?

    response = request(Net::HTTP::Post, "/contacts/upsert", locationId: location_id, email: email)
    contact_id = response.dig("contact", "id") or raise Error, "GHL upsert returned no contact id"

    request(Net::HTTP::Put, "/contacts/#{contact_id}", source: SOURCE) if response["new"]
    request(Net::HTTP::Post, "/contacts/#{contact_id}/tags", tags: [ SUBSCRIBER_TAG, source_tag(source), UNVERIFIED_TAG ])
    # Someone unsubscribing and coming back is subscribed again.
    request(Net::HTTP::Delete, "/contacts/#{contact_id}/tags", tags: [ UNSUBSCRIBED_TAG ])
    contact_id
  end

  # Looks the contact up rather than upserting: leaving the list must never
  # create a contact. Email do-not-disturb is deliberately not set; in a shared
  # account it would also stop every other business from emailing them.
  def self.unsubscribe(email:)
    return unless configured?

    query = URI.encode_www_form(locationId: location_id, email: email)
    contact_id = request(Net::HTTP::Get, "/contacts/search/duplicate?#{query}").dig("contact", "id")
    return unless contact_id

    request(Net::HTTP::Delete, "/contacts/#{contact_id}/tags", tags: [ SUBSCRIBER_TAG ])
    request(Net::HTTP::Post, "/contacts/#{contact_id}/tags", tags: [ UNSUBSCRIBED_TAG ])
    contact_id
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

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end
    raise Error, "GHL #{verb.name.demodulize.upcase} #{uri.path} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body.present? ? JSON.parse(response.body) : {}
  end

  def self.location_id = credentials[:location_id]

  def self.credentials = Rails.application.credentials.go_high_level || {}
end
