class SubscriberMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  # Sent once, when someone first joins the list. It exists to do the thing that
  # was promised on the form — hand over the routine sheet — rather than to
  # welcome anyone, so the link is the first thing in it.
  #
  # reply_to matters more than it looks. There is no unsubscribe link: the
  # message tells people to reply to stop, and the default sender is a
  # noreply@ address nobody reads. Without this, the only opt-out we offer
  # goes into a void, which is both rude and the sort of thing bulk-sender
  # rules exist to prevent.
  UNSUBSCRIBE_INBOX = "hello@remindly.care".freeze

  def welcome(subscriber)
    @subscriber = subscriber

    mail(
      to: subscriber.email,
      reply_to: UNSUBSCRIBE_INBOX,
      subject: "Your printable daily routine sheet"
    )
  end
end
