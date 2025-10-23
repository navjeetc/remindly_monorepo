namespace :audit do
  desc "Send daily audit report for yesterday's login/logout activity"
  task daily_report: :environment do
    # Get recipient email from environment variable or credentials
    recipient_email = ENV['AUDIT_REPORT_EMAIL'] || 
                     Rails.application.credentials.audit_report_email ||
                     Rails.application.credentials.admin_email

    if recipient_email.blank?
      puts "❌ Error: No recipient email configured"
      puts "Set AUDIT_REPORT_EMAIL environment variable or configure audit_report_email in credentials"
      exit 1
    end

    date = Date.yesterday
    puts "📧 Sending daily audit report for #{date.strftime('%B %d, %Y')} to #{recipient_email}..."

    begin
      AuditReportMailer.daily_report(
        date: date,
        recipient_email: recipient_email
      ).deliver_now

      puts "✅ Daily audit report sent successfully!"
    rescue => e
      puts "❌ Error sending audit report: #{e.message}"
      puts e.backtrace.join("\n")
      raise e
    end
  end

  desc "Send audit report for a specific date (usage: rake audit:report_for_date[2025-01-15,email@example.com])"
  task :report_for_date, [:date, :email] => :environment do |t, args|
    date = Date.parse(args[:date])
    recipient_email = args[:email] || 
                     ENV['AUDIT_REPORT_EMAIL'] || 
                     Rails.application.credentials.audit_report_email ||
                     Rails.application.credentials.admin_email

    if recipient_email.blank?
      puts "❌ Error: No recipient email provided"
      exit 1
    end

    puts "📧 Sending audit report for #{date.strftime('%B %d, %Y')} to #{recipient_email}..."

    begin
      AuditReportMailer.daily_report(
        date: date,
        recipient_email: recipient_email
      ).deliver_now

      puts "✅ Audit report sent successfully!"
    rescue => e
      puts "❌ Error sending audit report: #{e.message}"
      puts e.backtrace.join("\n")
      raise e
    end
  end

  desc "Preview today's audit report in console"
  task preview: :environment do
    date = Date.yesterday
    events = Ahoy::Event
      .includes(:user, :visit)
      .where(name: ["Login Success", "Login Failed", "Logout"])
      .where(time: date.beginning_of_day..date.end_of_day)
      .order(time: :desc)

    puts "\n" + "="*60
    puts "AUDIT REPORT PREVIEW - #{date.strftime('%B %d, %Y')}"
    puts "="*60

    successful_logins = events.where(name: "Login Success").count
    failed_logins = events.where(name: "Login Failed").count
    logouts = events.where(name: "Logout").count

    puts "\nSummary:"
    puts "  Total Events: #{events.count}"
    puts "  Successful Logins: #{successful_logins}"
    puts "  Failed Logins: #{failed_logins}"
    puts "  Logouts: #{logouts}"

    if events.any?
      puts "\nRecent Events:"
      events.limit(10).each do |event|
        puts "  #{event.time.strftime('%I:%M %p')} | #{event.user&.email || 'Unknown'} | #{event.name}"
      end
      puts "\n  ... and #{[events.count - 10, 0].max} more events" if events.count > 10
    else
      puts "\n  No events recorded for this date"
    end

    puts "\n" + "="*60 + "\n"
  end
end
