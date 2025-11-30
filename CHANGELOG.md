# Changelog

All notable changes to the Remindly project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.4] - 2025-11-25

### Added
- Automatic iPad voice-unlock listeners for the web client and Rails dashboard (voice unlock attempts fire after any tap)
- Enable Voice button in Advanced Options for the Rails dashboard (mirrors standalone web client)
- ⚙️ Settings button in the dashboard Advanced Options row so caregivers can access audio controls

### Changed
- Voice reminders now reuse the same unlock flow across hosted and standalone clients for consistency
- Improved caregiver-facing UI to surface voice settings and unlock affordance

### Fixed
- iPad reminders no longer stay silent until caregivers find a hidden enable control
- Voice unlock instructions now appear wherever the button exists (web client + dashboard)

### Security
- 


## [0.3.3] - 2025-11-10

### Added
- Calendar view for caregiver availability with toggle between list and calendar views
- Color-coded monthly calendar (green for available days, white for unavailable, gray for past)
- Display both start and end times on calendar days
- Month navigation (previous/next) for availability calendar
- Click-to-add functionality on calendar days
- Task unassign feature - caregivers can unassign themselves from tasks
- Task assignment notifications - assigned caregiver always notified
- Notification preference for caregivers to opt-in to notifications when tasks assigned to others
- New notification types: `task_available` and `task_assigned`
- "Unassign Me" button in task detail view with confirmation dialog

### Changed
- Updated how-to pages to clarify acknowledgment tracking (care receivers can acknowledge/snooze)
- Improved notification system to exclude caregiver from their own unassignment notification
- Enhanced availability view with persistent view preference (localStorage)

### Fixed
- Migration version updated to match Rails 8.0


## [0.3.2] - 2025-11-09

### Added
- Automated tests for critical bug fixes (11 tests, 45 assertions)
- Test infrastructure (test_helper.rb, fixtures)
- TEST_SUMMARY.md documentation

### Changed
- Improved performance: cached dev user queries to avoid N+1
- Improved performance: optimized coverage view with nested hash lookup (O(1))
- Use Date.current instead of Date.today for time zone consistency
- Enhanced error handling: replaced rescue nil with explicit logging

### Fixed
- **CRITICAL:** Fixed overlap detection bug in CaregiverAvailability (was checking end_time twice)
- **CRITICAL:** Fixed FeatureFlag.all method (was passing env_var instead of feature_key)
- Removed redundant where.not(id: nil) checks on primary keys
- Fixed misleading comments in CheckCoverageGapsJob
- Updated FEATURE_FLAGS.md last modified date

### Security
- N/A


## [0.3.1] - 2025-11-04

### Fixed
- Added comprehensive null checks for all DOM elements in voice_reminders.js to prevent runtime errors
- Fixed API filter to return both pending and acknowledged reminders for proper completion status display
- Re-enabled raise_on_missing_callback_actions in development environment for better error detection
- Added documentation comment explaining slow voice rate default (40% speed optimized for seniors)


## [0.3.0] - 2025-11-03

### Added
- Voice Reminders page with automatic text-to-speech announcements
- Browser-based speech synthesis for reminder announcements
- Done, Snooze (10 min), and Skip actions for reminders
- Acknowledgements system to track reminder completion
- Senior-friendly simplified UI with larger text and clearer layout
- Cross-browser speech synthesis support
- Timezone-aware reminder scheduling and display

### Changed
- Simplified Senior Dashboard to show only pending reminders prominently
- Completed reminders now collapsed in dropdown to reduce clutter
- Increased font sizes and button sizes for better accessibility
- Only announce reminder titles (not notes) to keep announcements concise
- Voice Reminders page uses timestamp-based cache busting for JavaScript

### Fixed
- Timezone display issues in new reminder form
- Voice announcements now work correctly across all modern browsers
- Duplicate announcement prevention
- JavaScript null reference errors in stats updates


## [0.2.8] - 2025-11-03

### Added
- App version display on public pages (login, how_to, contact) for easier debugging
- App version display in dashboard header for logged-in users

### Changed
- 

### Fixed
- Fixed NoMethodError when displaying app version on public pages (use APP_VERSION constant)

### Security
- 


## [0.2.7] - 2025-10-30

### Added
- 

### Changed
- 

### Fixed
- Fixed iPad mini icon sizing with additional responsive breakpoints
- Added md: breakpoint for medium tablets (including iPad mini)
- Icons now scale: h-4 w-4 (mobile) → h-5 w-5 (small tablets) → h-6 w-6 (medium tablets) → h-8-12 w-8-12 (desktop)
- Fixed task action icons, senior dashboard stats icons, and empty state icons
- Ensures proper sizing on iPad mini 7.9" displays

### Security
- 


## [0.2.6] - 2025-10-30

### Added
- 

### Changed
- 

### Fixed
- Fixed responsive icon sizing on tablets and iPads
- Icons now scale appropriately: smaller on mobile, medium on small tablets, full size on desktop
- Updated viewport meta tag for better tablet behavior
- Added responsive text sizing for main headings

### Security
- 


## [0.2.5] - 2025-10-24

### Added
- **How To page** with comprehensive descriptions of main features
  - Reminders functionality with custom schedules, categories, and voice announcements
  - Tasks functionality with assignment, scheduling, and status tracking
  - Browser compatibility note for voice announcements (all modern browsers supported)
  - Three video tutorial links:
    - How to Log In (magic link authentication)
    - How a Senior starts a request to connect with a Caregiver
    - How a Caregiver connects with a Senior
- **Contact Us page** with form for user feedback and support
  - Form fields: name, email, and message (all required)
  - Email notifications sent to admin_email via ContactMailer
  - HTML and text email templates with professional formatting
  - Reply-to set to submitter's email for easy responses
- **Navigation links** for How To and Contact Us pages in dashboard header

### Changed
- **Version management improved** - Version is now fetched dynamically via `/version` API endpoint
  - Web client automatically displays current version without hardcoding
  - Simplified bump_version.sh script (no longer needs to update HTML files)
  - Single source of truth for version (VERSION file + deploy.yml)

### Fixed
- 

### Security
-


## [0.2.4] - 2025-10-23

### Changed
- **Code quality improvements from PR feedback**
  - Use current time as default for new reminders (instead of hardcoded 09:00)
  - Simplified JSON request body parsing in magic_controller
  - Removed redundant getDefaultApiUrl() call in web client
  - Moved helper method inside namespace to avoid global pollution

### Fixed
- **Documentation improvements**
  - Clarified cron time format (12-hour input vs 24-hour output)
  - Use environment variables in cron documentation instead of hardcoded values


## [0.2.3] - 2025-10-23

### Added
- **Automated version bump script**
  - `bump_version.sh` now updates deploy.yml APP_VERSION
  - Auto-creates CHANGELOG.md entry template
  - Added deployment reminder to DEPLOYMENT_CHECKLIST.md

### Changed
- **Version management improvements**
  - Version fallback now checks multiple sources (monorepo VERSION, Rails VERSION, ENV)
  - Better documentation of version priority order
  - Removed hardcoded version fallbacks

### Fixed
- **Production version display**
  - Fixed "unknown" version in production
  - Added APP_VERSION to deployment environment variables


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
