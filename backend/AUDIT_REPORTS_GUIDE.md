# Audit Reports Guide

## Overview

Automated daily audit reports are sent via email every night at 10 PM, summarizing all login/logout activity from the previous day.

## Features

- **Daily Email Reports**: Automatically sent at 10 PM every night
- **Comprehensive Statistics**: Total events, successful logins, failed logins, and logouts
- **Activity by User**: Grouped view of each user's authentication activity
- **Detailed Event List**: Complete chronological list of all events
- **HTML & Plain Text**: Beautiful HTML emails with plain text fallback

## Configuration

### Set Recipient Email

The audit report recipient email can be configured in three ways (in order of precedence):

1. **Environment Variable** (Recommended for production):
   ```bash
   export AUDIT_REPORT_EMAIL="admin@example.com"
   ```

2. **Rails Credentials**:
   ```bash
   rails credentials:edit
   ```
   Add:
   ```yaml
   audit_report_email: admin@example.com
   ```

3. **Fallback to Admin Email**:
   Uses `admin_email` from credentials if no audit_report_email is set

### Cron Schedule

The schedule is defined in `config/schedule.rb`:

```ruby
# Daily audit report - runs every day at 10 PM
every 1.day, at: '10:00 pm' do
  rake "audit:daily_report"
end
```

To change the time, edit this file and update the crontab (see Deployment section).

## Manual Commands

### Send Today's Report Manually

```bash
rails audit:daily_report
```

### Send Report for Specific Date

```bash
rails audit:report_for_date[2025-01-15,admin@example.com]
```

### Preview Report in Console

```bash
rails audit:preview
```

This shows a text preview of yesterday's audit data without sending an email.

## Deployment

### Initial Setup

1. **Set the recipient email** (choose one method):
   
   **Option A: Environment Variable**
   ```bash
   # Add to .kamal/secrets
   AUDIT_REPORT_EMAIL=your@email.com
   ```
   
   **Option B: Rails Credentials**
   ```bash
   # On your local machine
   EDITOR=nano rails credentials:edit
   
   # Add:
   audit_report_email: your@email.com
   
   # Deploy the updated credentials
   kamal deploy
   ```

2. **Install crontab on server**:
   ```bash
   # SSH into the server
   ssh navjeetc@161.35.104.56
   
   # Navigate to the app directory
   cd /path/to/app
   
   # Update crontab
   bundle exec whenever --update-crontab
   
   # Verify crontab
   crontab -l
   ```

### Update Schedule

After changing `config/schedule.rb`:

```bash
# Deploy the changes
kamal deploy

# SSH into server and update crontab
ssh navjeetc@161.35.104.56
cd /path/to/app
bundle exec whenever --update-crontab
```

### Using Kamal

You can also update the crontab via Kamal:

```bash
kamal app exec 'bundle exec whenever --update-crontab'
```

## Cron Management Commands

### View Current Crontab

```bash
# On server
crontab -l

# Or via Kamal
kamal app exec 'crontab -l'
```

### Clear Crontab

```bash
# On server
bundle exec whenever --clear-crontab

# Or via Kamal
kamal app exec 'bundle exec whenever --clear-crontab'
```

### View Cron Logs

```bash
# On server
tail -f log/cron.log

# Or via Kamal
kamal app exec 'tail -f log/cron.log'
```

## Email Report Contents

### Summary Statistics
- Total authentication events
- Successful logins count
- Failed logins count
- Logout count

### Activity by User
- Grouped by user email
- Shows user role
- Lists all events for each user with timestamps

### All Events Table
Chronological list showing:
- Time
- User email
- Event type (Login Success/Failed, Logout)
- Authentication method
- Client type (web, API, etc.)
- IP address

## Troubleshooting

### Report Not Sending

1. **Check crontab is installed**:
   ```bash
   crontab -l
   ```

2. **Check cron logs**:
   ```bash
   tail -f log/cron.log
   ```

3. **Verify recipient email is configured**:
   ```bash
   rails runner "puts ENV['AUDIT_REPORT_EMAIL'] || Rails.application.credentials.audit_report_email || 'NOT SET'"
   ```

4. **Test email manually**:
   ```bash
   rails audit:daily_report
   ```

### Email Not Received

1. **Check Rails logs**:
   ```bash
   kamal app logs -f
   ```

2. **Verify email configuration**:
   - Check Postmark API token is set
   - Verify sender email is configured
   - Check spam folder

3. **Test with a different email**:
   ```bash
   rails audit:report_for_date[2025-01-15,test@example.com]
   ```

### Wrong Time Zone

The cron job runs in the server's time zone. To change:

1. Edit `config/schedule.rb` and adjust the time
2. Or set the time zone in the schedule file:
   ```ruby
   set :chronic_options, hours24: true
   ```

## Development Testing

### Test in Development

```bash
# Set recipient email
export AUDIT_REPORT_EMAIL="your@email.com"

# Run the task
rails audit:daily_report
```

In development, emails will open in your browser via `letter_opener` instead of being sent.

### Preview Without Sending

```bash
rails audit:preview
```

### Test Email Template

```bash
rails runner "AuditReportMailer.daily_report(date: Date.yesterday, recipient_email: 'test@example.com').deliver_now"
```

## Customization

### Change Report Frequency

Edit `config/schedule.rb`:

```ruby
# Every 12 hours
every 12.hours do
  rake "audit:daily_report"
end

# Every Monday at 9 AM (weekly)
every :monday, at: '9:00 am' do
  rake "audit:weekly_report"
end

# First day of month (monthly)
every '0 0 1 * *' do
  rake "audit:monthly_report"
end
```

### Customize Email Template

Edit the templates:
- HTML: `app/views/audit_report_mailer/daily_report.html.erb`
- Text: `app/views/audit_report_mailer/daily_report.text.erb`

### Add More Recipients

Modify `app/mailers/audit_report_mailer.rb`:

```ruby
def daily_report(date: Date.yesterday, recipient_email:)
  # ... existing code ...
  
  mail(
    to: recipient_email,
    cc: "security@example.com",  # Add CC
    subject: "Daily Audit Report - #{@date.strftime('%B %d, %Y')}"
  )
end
```

## Security Considerations

1. **Email Security**: Audit reports contain sensitive information (IP addresses, user activity)
2. **Recipient Access**: Only send to authorized personnel
3. **Email Encryption**: Use TLS for email delivery (configured in Postmark)
4. **Log Retention**: Consider implementing log retention policies
5. **Access Control**: Audit logs UI is admin-only, but email reports bypass this

## Future Enhancements

Potential additions:
- Weekly summary reports
- Monthly trend analysis
- Anomaly detection alerts
- Failed login threshold alerts
- CSV export attachment
- Configurable report recipients per user role
- Slack/Discord notifications
