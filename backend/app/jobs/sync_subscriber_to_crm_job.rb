# frozen_string_literal: true

# Makes GoHighLevel agree with the subscribers table for one address. A job
# rather than an inline call so a slow or failing GHL never delays, or breaks,
# the signup a stranger is waiting on.
#
# It carries no "subscribed" or "unsubscribed" of its own. It reads whether the
# address is on the list *now* and applies that. The first version replayed the
# event it was given, and with three worker threads and delayed retries a
# subscribe that ran late, after the same person had unsubscribed, put them back
# on the campaign list: emailing someone who opted out. Reading the current
# state means a stale or retried job can only ever re-apply the truth.
#
# One job per address at a time, so two of them cannot interleave their GHL
# calls either.
class SyncSubscriberToCrmJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(email) { email }, duration: 5.minutes

  # GHL refusing a request, or the network failing (GoHighLevel turns every
  # transport error into its own Error), is usually brief. After the last
  # attempt the job lands in Solid Queue's failed list, where it can be seen
  # and retried by hand.
  retry_on GoHighLevel::Error, wait: :polynomially_longer, attempts: 5

  def perform(email)
    # Without credentials there is nothing to do yet. Any pending removal stays
    # recorded, and subscribers:sync_to_crm replays both lists once they exist.
    return unless GoHighLevel.configured?

    # Unconfirmed is not on the list: a signup nobody has confirmed must not
    # reach the CRM, and someone who left and signed up again is off it until
    # they confirm again.
    if (subscriber = Subscriber.confirmed.find_by(email: email))
      GoHighLevel.subscribe(email: subscriber.email, source: subscriber.source)
    else
      GoHighLevel.unsubscribe(email: email)
      CrmRemoval.clear(email)
    end
  end
end
