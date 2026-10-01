# frozen_string_literal: true

# Mirrors a mailing-list signup or unsubscribe into GoHighLevel. A job rather
# than an inline call so a slow or failing GHL never delays, or breaks, the
# signup a stranger is waiting on.
#
# Takes the email rather than the record: by the time an unsubscribe runs, the
# Subscriber row is already gone.
class SyncSubscriberToCrmJob < ApplicationJob
  queue_as :default

  # GHL refusing a request, or the network failing, is usually brief. After the
  # last attempt the job lands in Solid Queue's failed list, where it can be
  # seen and retried by hand.
  retry_on GoHighLevel::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED,
    wait: :polynomially_longer, attempts: 5

  def perform(email:, change:, source: nil)
    case change.to_s
    when "subscribed" then GoHighLevel.subscribe(email: email, source: source)
    when "unsubscribed" then GoHighLevel.unsubscribe(email: email)
    else raise ArgumentError, "unknown change #{change.inspect}"
    end
  end
end
