# Same fact as users.email_undeliverable_at, for the other list mail goes to.
#
# Without it, a subscriber whose address Postmark has permanently refused gets
# re-enqueued by subscribers:send_monthly_note every single month, forever.
# MailDeliveryJob already discards that failure rather than raising it, so
# nothing breaks -- but nothing remembers it either, and the task keeps trying
# an address that will never again accept mail.
class AddEmailUndeliverableAtToSubscribers < ActiveRecord::Migration[8.1]
  def change
    add_column :subscribers, :email_undeliverable_at, :datetime
  end
end
