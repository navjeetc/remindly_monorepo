# Deletes signups nobody confirmed. The confirmation email promises the address
# is deleted after a week if it is not confirmed, and the privacy policy says
# the same; this is what keeps that promise. The link expires at the same
# moment, so nothing deleted here could still have been confirmed.
#
# An unconfirmed row never reached the CRM, so deleting it records no CRM
# removal and queues no sync (see Subscriber's callbacks).
class PruneUnconfirmedSubscribersJob < ApplicationJob
  queue_as :default

  def perform
    Subscriber.unconfirmed.where(created_at: ...Subscriber::CONFIRMATION_WINDOW.ago).find_each(&:destroy)
  end
end
