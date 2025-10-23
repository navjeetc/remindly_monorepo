# Ahoy Audit Logging Guide

## Overview

Ahoy has been integrated into Remindly to track user authentication events (login/logout) and provide comprehensive analytics capabilities.

## What's Tracked

### Login Events
- **Event Name**: `Login Success`
- **Properties**:
  - `method`: Authentication method used (`magic_link`, `magic_link_web`, `dev_login`, `dev_exchange`)
  - `client_type`: Client platform (`api`, `web`, `web_dashboard`)
  - `ip`: User's IP address
  - `user_agent`: Browser/client user agent

### Logout Events
- **Event Name**: `Logout`
- **Properties**:
  - `client_type`: Client platform
  - `ip`: User's IP address
  - `user_agent`: Browser/client user agent

### Failed Login Events
- **Event Name**: `Login Failed`
- **Properties**:
  - `reason`: Failure reason (`invalid_or_expired_token`)
  - `method`: Authentication method attempted
  - `client_type`: Client platform
  - `ip`: User's IP address
  - `user_agent`: Browser/client user agent

## Database Tables

### `ahoy_visits`
Tracks user sessions with:
- `visit_token`: Unique visit identifier
- `visitor_token`: Persistent visitor identifier
- `user_id`: Associated user (if authenticated)
- `ip`: IP address
- `user_agent`: Browser/client information
- `referrer`: Referring URL
- `landing_page`: First page visited
- `browser`, `os`, `device_type`: Detected from user agent
- `started_at`: Visit start time

### `ahoy_events`
Tracks individual events with:
- `visit_id`: Associated visit
- `user_id`: Associated user
- `name`: Event name (e.g., "Login Success")
- `properties`: JSON hash of event data
- `time`: Event timestamp

## Admin Web UI

### Accessing the Audit Logs UI

**Only admin users** can access the audit logs interface:

1. Log in to the dashboard as an admin user
2. Click **"Audit Logs"** in the top navigation
3. View, filter, and search through all authentication events

### Features

- **Event Filtering**: Filter by event type (Login Success, Login Failed, Logout)
- **User Filtering**: View events for specific users
- **Date Range**: Filter events by date range
- **Statistics**: View total events, successful logins, and failed logins
- **Detailed View**: Click "Details" on any event to see complete information
- **Pagination**: Browse through events 50 at a time

### Access Control

The audit logs are protected by:
- `authenticate!` - Requires user to be logged in
- `require_admin!` - Requires user to have admin role

Non-admin users attempting to access `/admin/audit_logs` will be redirected to the dashboard with an "Access denied" message.

## Querying Audit Logs

### View all login events for a user
```ruby
user = User.find_by(email: "user@example.com")
user.events.where(name: "Login Success")
```

### View recent login failures
```ruby
Ahoy::Event.where(name: "Login Failed").order(time: :desc).limit(10)
```

### View all events for a specific visit
```ruby
visit = Ahoy::Visit.find_by(visit_token: "abc123")
visit.events
```

### Get login statistics
```ruby
# Count logins by method
Ahoy::Event.where(name: "Login Success")
  .group("properties->>'method'")
  .count

# Count logins by client type
Ahoy::Event.where(name: "Login Success")
  .group("properties->>'client_type'")
  .count
```

### View user's login history
```ruby
user = User.find(123)
user.events.where(name: ["Login Success", "Login Failed", "Logout"])
  .order(time: :desc)
```

### Get all visits for a user
```ruby
user = User.find(123)
user.visits.order(started_at: :desc)
```

## Configuration

Configuration is in `config/initializers/ahoy.rb`:

- **Visit Duration**: 4 hours (new visit created after 4 hours of inactivity)
- **Visitor Duration**: 2 years (new visitor token after 2 years)
- **Bot Tracking**: Enabled in development, disabled in production
- **Geocoding**: Disabled (can be enabled with geocoder gem)

## Rails Console Examples

```ruby
# Find suspicious login attempts (multiple failures)
failed_logins = Ahoy::Event.where(name: "Login Failed")
  .group("properties->>'ip'")
  .having("count(*) > 5")
  .count

# View recent user activity
user = User.find_by(email: "user@example.com")
user.events.order(time: :desc).limit(20).each do |event|
  puts "#{event.time}: #{event.name} - #{event.properties}"
end

# Get login count by day
Ahoy::Event.where(name: "Login Success")
  .group_by_day(:time)
  .count

# Find users who logged in today
today_logins = Ahoy::Event.where(name: "Login Success")
  .where("time >= ?", Time.current.beginning_of_day)
  .pluck(:user_id)
  .uniq
User.where(id: today_logins)
```

## Security Considerations

1. **IP Address Storage**: IP addresses are stored for audit purposes. Consider privacy regulations (GDPR, etc.)
2. **Data Retention**: Consider implementing a data retention policy to delete old audit logs
3. **Access Control**: Restrict access to audit logs to admin users only

## Automated Email Reports

Daily audit reports are automatically sent via email every night at 10 PM, summarizing all login/logout activity from the previous day.

**Features:**
- Comprehensive statistics (total events, success/fail counts)
- Activity grouped by user
- Detailed event listings with IP addresses
- Beautiful HTML emails with plain text fallback

**See:** `AUDIT_REPORTS_GUIDE.md` for complete documentation on:
- Configuration and setup
- Manual commands
- Deployment instructions
- Troubleshooting
- Customization options

**Quick Start:**
```bash
# Set recipient email
export AUDIT_REPORT_EMAIL="admin@example.com"

# Test manually
rails audit:daily_report

# Preview without sending
rails audit:preview
```

## Future Enhancements

Potential additions:
- Geocoding to track login locations
- Anomaly detection for suspicious login patterns
- Real-time alerts for unusual login activity
- Weekly and monthly trend reports
- Export functionality for compliance reporting
