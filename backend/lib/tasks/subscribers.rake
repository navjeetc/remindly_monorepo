# frozen_string_literal: true

namespace :subscribers do
  desc "Send this month's note to every subscriber. Edit the content first: " \
       "app/views/subscriber_mailer/monthly_note.html.erb and .text.erb. Requires CONFIRM=yes. " \
       "Not idempotent -- running it twice with CONFIRM=yes resends to everyone twice."
  task send_monthly_note: :environment do
    count = Subscriber.count

    if count.zero?
      puts "No subscribers — nothing to send."
      next
    end

    # A dry run by default, not a flag to remember. This sends real mail to
    # real people, and running the bare task is the easy way to check who it
    # would reach before it reaches them — not a second way to accidentally
    # send it.
    unless ENV["CONFIRM"] == "yes"
      puts "Would send to #{count} #{'subscriber'.pluralize(count)}:"
      Subscriber.order(:created_at).each { |s| puts "  #{s.email}" }
      puts ""
      puts "Nothing has been sent. Review the content in"
      puts "app/views/subscriber_mailer/monthly_note.html.erb and .text.erb, then run:"
      puts "  CONFIRM=yes bin/rails subscribers:send_monthly_note"
      next
    end

    puts "Queuing #{count} #{'subscriber'.pluralize(count)}..."

    # deliver_later, not deliver_now. Production raises on delivery failure,
    # and one bad address -- Postmark has marked plenty inactive, a hard
    # bounce means the mailbox no longer exists -- would otherwise raise out
    # of this loop and leave everyone after it in Subscriber.find_each order
    # unmailed, with no record of who that was.
    #
    # deliver_later routes through MailDeliveryJob, already written for
    # exactly this failure and already covered by its own specs: a permanent
    # refusal is discarded and logged rather than raised, and it cannot take
    # down a send to anyone else, because each recipient is its own job.
    #
    # What this does not do is protect against running the task itself twice.
    # There is no record on Subscriber of a month already sent, which is fine
    # for a send a person runs once by hand and wrong the day this needs to
    # run unattended -- see subscribers.rake's desc.
    Subscriber.find_each do |subscriber|
      SubscriberMailer.monthly_note(subscriber).deliver_later
      puts "  ✓ #{subscriber.email}"
    end

    puts "Queued. Running CONFIRM=yes again before the next real month would resend to everyone above."
  end
end
