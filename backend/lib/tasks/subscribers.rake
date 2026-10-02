# frozen_string_literal: true

namespace :subscribers do
  desc "Send this month's note to every subscriber. Edit the content first: " \
       "app/views/subscriber_mailer/monthly_note.html.erb and .text.erb. Requires CONFIRM=yes. " \
       "Not idempotent -- running it twice with CONFIRM=yes resends to everyone twice."
  task send_monthly_note: :environment do
    # .deliverable, not .all: an address MailDeliveryJob has already discarded
    # once is going to be discarded again, forever, and re-enqueuing it every
    # month is a doomed send with no result other than noise in the log.
    #
    # .confirmed: an unconfirmed signup has not joined the list (double opt-in).
    recipients = Subscriber.confirmed.deliverable
    count = recipients.count
    skipped = Subscriber.confirmed.count - count

    if count.zero?
      puts "No subscribers — nothing to send."
      puts "(#{skipped} marked undeliverable, skipped)" if skipped.positive?
      next
    end

    # A dry run by default, not a flag to remember. This sends real mail to
    # real people, and running the bare task is the easy way to check who it
    # would reach before it reaches them — not a second way to accidentally
    # send it.
    unless ENV["CONFIRM"] == "yes"
      puts "Would send to #{count} #{'subscriber'.pluralize(count)}:"
      recipients.order(:created_at).each { |s| puts "  #{s.email}" }
      puts "(#{skipped} more marked undeliverable, skipped)" if skipped.positive?
      puts ""
      puts "Nothing has been sent. Review the content in"
      puts "app/views/subscriber_mailer/monthly_note.html.erb and .text.erb, then run:"
      puts "  CONFIRM=yes bin/rails subscribers:send_monthly_note"
      next
    end

    puts "Queuing #{count} #{'subscriber'.pluralize(count)}..."
    puts "(#{skipped} marked undeliverable, skipped)" if skipped.positive?

    # deliver_later, not deliver_now. Production raises on delivery failure,
    # and one bad address -- Postmark has marked plenty inactive, a hard
    # bounce means the mailbox no longer exists -- would otherwise raise out
    # of this loop and leave everyone after it in Subscriber.find_each order
    # unmailed, with no record of who that was.
    #
    # deliver_later routes through MailDeliveryJob, already written for
    # exactly this failure and already covered by its own specs: a permanent
    # refusal is discarded and logged rather than raised — and now marks the
    # address on Subscriber too, which is what .deliverable above reads, so a
    # bounce this run is skipped on every run after it rather than retried
    # forever. One failure still cannot take down a send to anyone else,
    # because each recipient is its own job.
    #
    # What this does not do is protect against running the task itself twice
    # in the same month. There is no record of a month already sent, which is
    # fine for a send a person runs once by hand and wrong the day this needs
    # to run unattended -- see this task's desc.
    recipients.find_each do |subscriber|
      SubscriberMailer.monthly_note(subscriber).deliver_later
      puts "  ✓ #{subscriber.email}"
    end

    puts "Queued. Running CONFIRM=yes again before the next real month would resend to everyone above."
  end

  # The GHL sync does nothing until its credentials exist, and a signup in that
  # time is not queued to happen later. Run this once after adding them: it
  # makes GHL agree with the table for every current subscriber, and removes
  # everyone who unsubscribed meanwhile (kept in crm_removals until then).
  desc "Make GoHighLevel agree with the subscribers table (run once after adding GHL credentials)"
  task sync_to_crm: :environment do
    abort "GoHighLevel credentials are not configured; nothing to sync." unless GoHighLevel.configured?

    subscribers = Subscriber.confirmed.pluck(:email)
    removals = CrmRemoval.pluck(:email)
    (subscribers | removals).each { |email| SyncSubscriberToCrmJob.perform_later(email) }
    puts "Queued #{subscribers.size} subscriber#{'s' unless subscribers.size == 1} " \
         "and #{removals.size} removal#{'s' unless removals.size == 1} for GoHighLevel."
  end

  # Run once, right after the 0.21.0 deploy that made the list double opt-in.
  #
  # Kamal runs the migration that marks every existing subscriber confirmed
  # while the old container is still serving. Anyone who signed up in those
  # seconds went through the old single opt-in path -- welcome email, our
  # notification, CRM sync -- but their row was written after the migration,
  # so it is unconfirmed: they would never be asked to confirm, and the prune
  # job would delete them a week later.
  #
  # The new code records confirmation_sent_at on every signup, so an
  # unconfirmed row without one can only have come from the old code. The
  # one-minute margin keeps clear of a new signup between its insert and the
  # send that follows it. Confirming sends nothing (the welcome email is the
  # controller's, not confirm!'s); the CRM sync it queues re-applies what the
  # old code already did.
  desc "Once, after the 0.21.0 deploy: confirm single opt-in signups written during the cutover"
  task grandfather_cutover_signups: :environment do
    stragglers = Subscriber.unconfirmed.where(confirmation_sent_at: nil).where(created_at: ...1.minute.ago)
    emails = stragglers.pluck(:email)
    stragglers.find_each(&:confirm!)
    puts "Confirmed #{emails.size} signup#{'s' unless emails.size == 1} from the cutover" +
         (emails.any? ? ": #{emails.join(', ')}" : ".")
  end
end
