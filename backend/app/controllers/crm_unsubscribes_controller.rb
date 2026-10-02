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
# the body. `secret` and `email` are both in filter_parameters, so neither
# reaches the logs.
#
# Leaving goes through Subscriber#destroy, the same path as Remindly's own
# unsubscribe link: it records the pending CRM removal and queues the sync job,
# which deletes the contact from GHL if it is purely Remindly's.
class CrmUnsubscribesController < ApplicationController
  before_action :verify_secret

  def create
    if (email = unsubscribed_email)
      Subscriber.find_by(email: email.strip.downcase)&.destroy
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
  def unsubscribed_email
    params[:email].presence || params.dig(:contact, :email).presence
  end

  # Refuses everything until a secret is configured, so the endpoint cannot be
  # used to delete subscribers before it has been set up on purpose.
  def verify_secret
    expected = GoHighLevel.webhook_secret
    given = params[:secret].to_s

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

    head :unauthorized
  end
end
