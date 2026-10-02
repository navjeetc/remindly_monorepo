# frozen_string_literal: true

# GoHighLevel telling Remindly that a mailing-list contact unsubscribed there.
#
# Campaigns go out from GHL, carrying GHL's own unsubscribe link. Without this,
# someone who used it stayed a Subscriber here: the privacy policy promises the
# address is deleted when they ask to stop, and the Rails monthly note (kept as
# a fallback sender) could still reach them.
#
# A GHL workflow calls this (trigger: email DND enabled / unsubscribed, filtered
# to the remindly-subscriber tag; action: the standard Webhook, POST, with a
# custom data field `secret`). The standard action cannot send custom headers
# (that needs the paid Custom Webhook action), so the shared secret travels in
# the body, under `customData` (where that action puts custom data). `secret`
# and `email` are both in filter_parameters, so neither reaches the logs.
#
# Leaving goes through Subscriber#destroy, the same path as Remindly's own
# unsubscribe link: it records the pending CRM removal and queues the sync job,
# which deletes the contact from GHL if it is purely Remindly's.
class CrmUnsubscribesController < ApplicationController
  before_action :verify_secret

  def create
    if (email = unsubscribed_email)
      Subscriber.find_by(email: email)&.destroy
    else
      Rails.logger.warn("CRM unsubscribe webhook arrived without an email")
    end

    # 200 whether or not the address was on the list: the answer must not tell
    # a caller who is subscribed, and GHL has nothing to retry either way.
    head :ok
  end

  private

  # GHL's standard webhook puts the contact's fields at the top level; accept a
  # nested contact too, in case the workflow maps it that way.
  #
  # Only a non-blank string counts. A malformed payload (an object where the
  # email should be, or a string where the contact should be) raised on strip or
  # dig, and the 500 made GHL retry what this endpoint means to answer, once,
  # with 200. Anything that is not a usable string is treated like no email.
  def unsubscribed_email
    contact = params[:contact]
    candidates = [ params[:email], (contact[:email] if contact.respond_to?(:key?)) ]
    email = candidates.find { |value| value.is_a?(String) && value.strip.present? }
    email&.strip&.downcase
  end

  # GHL's standard Webhook action nests the workflow's custom data under
  # `customData`, alongside the contact's fields at the top level. The first
  # live call (2026-10-02) sent {"email": ..., "customData": {"secret": ...}}
  # and was refused, because only a top-level `secret` was read. Both are
  # accepted; only a string counts, like the email.
  def given_secret
    custom = params[:customData]
    candidates = [ params[:secret], (custom[:secret] if custom.respond_to?(:key?)) ]
    candidates.find { |value| value.is_a?(String) && value.present? }.to_s
  end

  # Refuses everything until a secret is configured, so the endpoint cannot be
  # used to delete subscribers before it has been set up on purpose.
  def verify_secret
    expected = GoHighLevel.webhook_secret
    given = given_secret

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    head :unauthorized
  end
end
