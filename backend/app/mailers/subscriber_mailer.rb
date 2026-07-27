class SubscriberMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  # Sent once, when someone first joins the list. It exists to do the thing that
  # was promised on the form — hand over the routine sheet — rather than to
  # welcome anyone, so the link is the first thing in it.
  def welcome(subscriber)
    @subscriber = subscriber

    mail(
      to: subscriber.email,
      subject: "Your printable daily routine sheet"
    )
  end
end
