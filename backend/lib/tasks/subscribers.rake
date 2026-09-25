namespace :subscribers do
  desc "Send this month's note to every subscriber. Edit the content first: " \
       "app/views/subscriber_mailer/monthly_note.html.erb and .text.erb. Requires CONFIRM=yes."
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

    puts "Sending to #{count} #{'subscriber'.pluralize(count)}..."

    Subscriber.find_each do |subscriber|
      SubscriberMailer.monthly_note(subscriber).deliver_now
      puts "  ✓ #{subscriber.email}"
    end

    puts "Done."
  end
end
