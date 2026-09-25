class SubscriberMailer < ApplicationMailer
  # Sent once, when someone first joins the list. It exists to do the thing that
  # was promised on the form — hand over the routine sheet — rather than to
  # welcome anyone, so the link is the first thing in it.
  #
  # reply_to matters more than it looks. There is no unsubscribe link: the
  # message tells people to reply to stop, so replies have to reach a mailbox
  # someone reads. Without this, the only opt-out we offer
  # goes into a void, which is both rude and the sort of thing bulk-sender
  # rules exist to prevent.
  UNSUBSCRIBE_INBOX = OFFICIAL_EMAIL

  def welcome(subscriber)
    @subscriber = subscriber

    mail(
      to: subscriber.email,
      reply_to: UNSUBSCRIBE_INBOX,
      subject: "Your printable daily routine sheet"
    )
  end

  # Tells us when someone joins. At this size that is worth knowing as it
  # happens — a list of one is a person, not a metric — and the source is the
  # part that pays: it says which page earned the address, which is the only
  # honest way to find out which writing is worth doing more of.
  #
  # reply_to is the subscriber, so answering the notification writes to them
  # directly. For a list this small that is a feature, not a slip.
  def new_subscriber(subscriber)
    @subscriber = subscriber
    @total = Subscriber.count

    mail(
      to: self.class.admin_recipient,
      reply_to: subscriber.email,
      subject: "New Remindly subscriber: #{subscriber.email}"
    )
  end

  # The "about once a month" note the welcome email promises — the one thing
  # kept from that promise, and for a while the only thing that wasn't: it was
  # promised on 2026-07-27 and nothing had gone out by 2026-09-24.
  #
  # Content lives in the view and is edited by hand before each send — no
  # admin UI, no stored copy, nothing scheduled to fire on its own. Right for a
  # list this size, and it stays that way only for as long as somebody notices
  # when a month has passed; see lib/tasks/subscribers.rake for the send.
  #
  # reply_to matches welcome, for the same reason: there is still no
  # unsubscribe link, so replying is still the only way out, and it has to
  # reach a mailbox someone reads every time, not just the first time.
  def monthly_note(subscriber)
    @subscriber = subscriber

    mail(
      to: subscriber.email,
      reply_to: UNSUBSCRIBE_INBOX,
      subject: "One thing for this month, from Remindly"
    )
  end
end
