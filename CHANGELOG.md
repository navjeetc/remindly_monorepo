# Changelog

All notable changes to the Remindly project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2025-10-23

### Fixed
- **Web client magic link routing**
  - Fixed web client to send `client=web` parameter
  - Magic links now correctly point to `/client/` instead of `/magic/verify`
  - Updated cache buster to force browser reload of updated JavaScript
  - Fixed version display in web client UI

## [0.2.1] - 2025-10-23

### Security
- **Improved magic link security**
  - Web client now uses POST instead of GET for token verification
  - Prevents token exposure in server logs, browser history, and referer headers
  - Backend supports both GET (email links) and POST (API) for backward compatibility

### Changed
- **Simplified web client detection**
  - Removed fragile referer-based detection
  - Now uses only explicit `client=web` parameter
  - More reliable and maintainable

### Fixed
- **Cross-platform compatibility**
  - Fixed `bump_version.sh` to work on both macOS and Linux
  - Detects OS and uses appropriate sed syntax
- **Code quality improvements**
  - Fixed misleading comments in magic_mailer.rb
  - Added detailed rationale for bot tracking in ahoy.rb
  - Extracted recipient email resolution into reusable helper method
  - Documented timezone assumption in cron schedule

### Added
- Test scripts for verifying magic link functionality
  - `test_magic_links.sh` - Tests different client types
  - `test_magic_post.sh` - Verifies GET and POST methods

## [0.2] - 2025-10-23

### Added
- **Audit Logging System** with Ahoy gem
  - Track all login/logout events with IP addresses and user agents
  - Admin-only UI for viewing audit logs at `/admin/audit_logs`
  - Filter audit logs by event type, user, and date range
  - Detailed event view with visit information
  - Statistics dashboard showing success/fail counts

- **Automated Daily Audit Reports**
  - Email reports sent automatically at 10 PM daily
  - Beautiful HTML email template with statistics
  - Plain text email fallback
  - Summary statistics (total events, success/fail/logout counts)
  - Activity grouped by user with role badges
  - Complete event listing with timestamps, methods, and IPs
  - Manual report generation: `rails audit:daily_report`
  - Custom date reports: `rails audit:report_for_date[date,email]`
  - Preview command: `rails audit:preview`

- **Cron Job Management**
  - Whenever gem for cron job scheduling
  - Configured to run daily at 10 PM
  - Comprehensive setup documentation

### Documentation
- `AHOY_AUDIT_GUIDE.md` - Complete audit logging guide
- `AUDIT_REPORTS_GUIDE.md` - Email reports documentation
- `CRON_SETUP.md` - Cron job setup instructions

### Technical
- Added `ahoy_matey` gem (~> 5.2)
- Added `whenever` gem (~> 1.0)
- Added `kaminari` gem (~> 1.2) for pagination
- Created `ahoy_visits` and `ahoy_events` database tables
- User model associations for visits and events

## [0.1] - 2025-10-22

### Added
- **Initial Release**
- Core reminder system for seniors
- Magic link authentication (email-based, passwordless)
- Caregiver pairing system with token-based linking
- Task management for caregivers and seniors
- Voice web client for seniors
- Dashboard for caregivers
- User roles: Senior, Caregiver, Admin
- Admin user management interface
- Email delivery via Postmark
- SQLite database
- Docker deployment with Kamal
- Production deployment on DigitalOcean

### Features
- **Reminders**
  - Create, edit, delete reminders
  - Recurring reminders with ice_cube
  - Reminder acknowledgements
  - Snooze functionality
  - Today's reminders view

- **Authentication**
  - Magic link login (web and API)
  - JWT token-based sessions
  - Dev mode quick login
  - Session management

- **Caregiver Features**
  - Pair with seniors using tokens
  - View senior's reminder activity
  - Create reminders for seniors
  - Task assignments
  - Availability scheduling

- **Admin Features**
  - User management
  - Role assignment
  - View all users and relationships

### Technical Stack
- Ruby on Rails 8.0.3
- Ruby 3.3.5
- SQLite database
- Puma web server
- Postmark for emails
- JWT for authentication
- Docker containerization
- Kamal deployment
- TailwindCSS for styling

### Documentation
- Phase 5 Authentication Guide
- Sprint 5 Implementation Guide
- Setup instructions
