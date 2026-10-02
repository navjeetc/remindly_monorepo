# Deletes signups nobody confirmed. The confirmation email says an address
# nobody confirms is deleted after a week, and the privacy policy says the
# same; this is what keeps that promise.
#
# Measured from the latest confirmation email, not the signup. Every resend
# mints a link that works for another seven days, and counting from the
# signup deleted the row, and so killed that link, within hours of sending it.
# From the latest send, the row outlives every link issued for it.
#
# One DELETE with the conditions in it, rather than loading rows and then
# destroying them: a person who confirmed between the load and the destroy was
# deleted anyway, by an object that still thought they were unconfirmed. Here
# the database decides, row by row, at the moment of deletion. Skipping
# callbacks loses nothing: an unconfirmed row never reached the CRM, so there
# is no removal to record and no sync to queue (see Subscriber's callbacks).
class PruneUnconfirmedSubscribersJob < ApplicationJob
  queue_as :default

  def perform
    Subscriber.unconfirmed
      .where("COALESCE(confirmation_sent_at, created_at) < ?", Subscriber::CONFIRMATION_WINDOW.ago)
      .delete_all
  end
end
