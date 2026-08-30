# frozen_string_literal: true

# The job every `deliver_later` runs through.
#
# It exists for one reason: a permanently refused address is not a temporary
# failure, and Rails treats every delivery error as one. Postmark rejects mail to
# an address it has marked inactive — an address that has hard bounced, meaning
# the mailbox does not exist — and the default behaviour was to retry that,
# exhaust the retries, and record a failure. Every morning. Forty-four times
# between 2026-07-24 and 2026-08-09 before anyone noticed, because a job that
# fails quietly looks exactly like one that is not running.
#
# Retrying cannot help: Postmark has already decided, and it decided on evidence
# from the receiving server. So the error is discarded rather than retried, and
# the address is recorded so nothing initiates the send next time.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  # `discard_on` rather than a rescue: this is not a failure to recover from,
  # it is an instruction. Raising again would put the job back in the failed
  # queue and hide the failures that do deserve attention.
  discard_on Postmark::InactiveRecipientError do |job, error|
    # The gem parses the addresses out of Postmark's message for us, so there is
    # no need to match on the wording — which is theirs to change.
    addresses = error.try(:recipients).presence || []

    marked = User.where(email: addresses).map do |user|
      user.mark_email_undeliverable!
      user.email
    end

    unmatched = addresses - marked

    Rails.logger.warn(
      "MailDeliveryJob: #{job.arguments.first}##{job.arguments.second} discarded — " \
      "Postmark has permanently refused #{addresses.join(", ").presence || "the recipient"}. " \
      "Marked undeliverable: #{marked.presence&.join(", ") || "none"}. " \
      "No matching user: #{unmatched.presence&.join(", ") || "none"}."
    )
  end
end
