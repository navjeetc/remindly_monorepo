# frozen_string_literal: true

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
end
