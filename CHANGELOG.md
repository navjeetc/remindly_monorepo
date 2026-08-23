# Changelog

All notable changes to the Remindly project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **Telnyx webhooks failed open when no token was configured**: a blank
  `webhook_token` meant "accept anything", which reads as a lenient default and
  is actually an open door — production has no `telnyx:` credentials, so on
  deploy `/telnyx/webhooks` would have accepted any POST and let it acknowledge
  a reminder. An unconfigured integration now rejects callbacks instead of
  trusting them, and the token comparison is constant-time.
- **The `base_url` credential still pointed at the legacy domain**: it said
  `remindly.anakhsoft.com`, and two places in the codebase had already been
  written to route around it — the production mailer host is hardcoded because
  the credential "was stale and kept sending caregivers to the old domain", and
  `MagicMailer` prefers the origin the login actually began on. It is now
  `www.remindly.care`, matching `ApplicationHelper::CANONICAL_HOST`, so email
  links, canonical tags and Telnyx callbacks finally agree on one host. The
  mailer host stays hardcoded regardless: login links are the
  highest-consequence path in the app.

### Added
- **Reminders delivered as a phone call, acknowledged from the keypad**: every
  client until now assumed the senior has a screen, is signed in, and will look
  at it. A phone call assumes none of that — it reaches someone whose only
  device is a landline, and it reaches them whether or not they remember an app
  exists. At the scheduled time Telnyx dials the senior, speaks the reminder and
  collects one digit: 1 marks it done, 2 schedules it again ten minutes later.
  Those are the same two actions `/voice_reminders` offers, and both now run
  through `Occurrence#snooze!`, so a keypress and a tap cannot drift apart — a
  snooze resolves the occurrence *and* schedules the next one, which recording
  the acknowledgement alone would not. An unanswered call records `no_response`
  and leaves the occurrence pending, deliberately not "skip": nobody chose
  anything, so the missed sweep still claims it and the caregiver is still told.

  **Not yet fit to enable in production.** There is no consent record, no
  calling-hours guard in the called party's own timezone — `recurring.yml` would
  run the scheduler every minute, at any hour — and no answering-machine
  detection. `docs/PHONE_CALL_REMINDERS_DESIGN.md` sets out what has to exist
  first, and why the timezone bug fixed in August is load-bearing here: a user
  silently moved to UTC-12 gets telephoned in the middle of the night.

  Each call carries its own `webhook_url`, resolved from `base_url` or
  `APP_URL`, which overrides the one configured on the Telnyx connection. A
  single URL in the provider's portal has to be hand-flipped between production
  and a tunnel to test anything, and forgetting has no error: the call
  connects, nothing is listening, and the senior hears silence until it times
  out. A base that resolves to loopback sends no override at all rather than a
  URL Telnyx provably cannot reach.

- **A landing page at `/reminder-app-for-elderly-parents`**: the homepage opens
  on the feeling — "caring for a parent from a distance" — because most people
  who reach it arrived from a link someone sent them and are already part
  persuaded. Someone typing "reminder app for elderly parents" into a search
  engine has already decided they want software and is asking which one, and
  that search had no page here to land on. This one answers it in its own words:
  what a reminder app has to do when the person needing reminding and the person
  arranging it are not in the same house, how Remindly does each, what it runs
  on, and what comes back to the caregiver. It asks three questions of its own —
  is it worth it if they only take one tablet, will they find it patronising,
  what if it does not suit us — and publishes no `FAQPage`: `/faq` keeps that
  graph. Two pages of ours bidding for the same informational search compete
  with each other, and rewording the questions does not separate them, because
  what competes is the intent behind them. Held to the same claims as the rest
  of the site: "marked done", never "taken", and the page-must-stay-open
  limitation stated rather than buried.
- **A count of public page views, that records nobody**: the marketing pages set
  no analytics cookie and write no Ahoy visit, which is what makes the privacy
  policy true — and it left us unable to answer the only question that mattered
  after posting about Remindly on a forum: did it send nobody, or send people
  who bounced? Those call for opposite responses, and the fallback of grepping
  the server logs holds about a week. `PageCount` keeps one row per day per
  page, referring site, campaign tag and human/bot, with a counter. No visitor
  id, no IP address, no user agent, no cookie: the user agent is read to
  classify the request and thrown away, and a referrer is reduced to its host
  because referrer paths carry search terms. A `?from=` tag on a link we share
  survives forums that strip the referrer. Readable at **Admin → Traffic**, and
  deleted after 90 days by `PruneAnalyticsJob`, which is what the privacy policy
  promises. The policy is updated to describe exactly what is now kept.
- **The site can be found**: `/sitemap.xml`, generated from the routes and the
  posts on disk rather than kept as a static file, and advertised in
  `robots.txt`. `SoftwareApplication` structured data declaring a price of 0 —
  which is what lets a result carry a "free" label — plus `og:image` and
  `twitter:card`, without which every shared link rendered as a bare grey box.
- **`/faq`**: the questions caregivers type into a search engine, with
  `FAQPage` structured data so answers can surface directly in results.
  Questions and answers render from one source, because Google drops a
  `FAQPage` whose questions are not also visible on the page.
- **Blog at `/blog`**: posts are Markdown files in `backend/content/posts` with
  YAML front matter — no database table, no admin UI. Publishing is adding a
  file; the index, the sitemap and the `Article` structured data all pick it up.
  A `published_on` in the future is a draft.
- **Printable daily routine sheet at `/routine_sheet`**: one page for the fridge
  door, deliberately not gated behind the mailing list.
- **Mailing list**: signup on the public pages, with the routine sheet emailed
  on joining, and a notification to us naming the page that earned the address.
- **Product screenshots on the homepage**: real captures of the voice reminders
  page and the caregiver task list, scripted so they can be regenerated when the
  UI changes (`backend/script/marketing_screenshots`).
- **It says that it is free**: in the title of every page written to be landed
  on, a badge beside the logo, and a "why is it free — what's the catch?" FAQ
  entry, since answering the suspicion is worth more than repeating the word.
- **Free printable caregiver checklist at `/caregiver_checklist`**: a one-page
  weekly sheet with a box for each day — morning, through the day, evening, plus
  the weekly things that quietly cause a crisis if nobody looks. Ungated, like
  the routine sheet: a free printable is the one asset here that a senior centre
  or a caregiver forum might link to, and backlinks are what a new domain lacks.
- **Two more blog posts**: building a medication routine that sticks, and what to
  check on daily when a parent lives alone.
- **Navigation at the top of every public page**: How it works, Questions and
  Blog. Someone arriving on a post from a search previously had no visible route
  anywhere except Sign in — the one thing they are not ready to do. Three links,
  not the footer's seven, and no JavaScript: they stack under the logo on a
  narrow screen rather than hiding behind a menu.
- **`Organization` and `WebSite` structured data on every public page**, which is
  the association search engines use to tie a domain, a name and a support
  address together. Nothing declared it before.

### Changed
- **All mail now sends from `hello@remindly.care`**, defined once on
  `ApplicationMailer`. Seven of the eight mailers previously fell back to
  `noreply@remindly.app` — a domain that is not ours and that Postmark rejects
  outright — or sent from a personal address on another domain. Who receives
  contact submissions and subscriber notices stays configurable.
- **The task list shows a senior's name** rather than their email address.

### Fixed
- **Saving your profile could move you to UTC-12.** The timezone column had
  drifted into holding two spellings of the same thing — IANA identifiers
  (`America/New_York`, the column default) and Rails zone names (`Eastern Time
  (US & Canada)`, what the profile form submitted). Nothing ever failed on it,
  because every read goes through `ActiveSupport::TimeZone[]` and that accepts
  either, which is exactly why the mixture sat there unnoticed. The round trip
  is where it broke: the select's option values were Rails names, so a user
  whose column held the IANA default matched no option at all, the browser fell
  back to the first entry in the list — International Date Line West — and
  saving the form wrote it back. Changing your name moved you seventeen hours
  off Eastern, and in an app whose entire job is firing reminders at the right
  moment, that means every reminder lands on the wrong day. It happened to the
  first real signup, on her first day, and raised nothing anywhere. Zones are
  now normalized to the identifier on write, a zone that resolves to nothing is
  rejected instead of stored, and the select offers the same identifiers it
  stores so the round trip closes. A migration brings the existing rows across.
- **The traffic counter was calling scanners people.** Two days after shipping,
  the human figure was overstating by roughly two and a half times: 43 "human"
  views on 10 August against 18 favicon fetches, which is the number of requests
  a real browser actually made. The cause was the classifier being a denylist
  only, so anything without a recognisable bot token counted as a person —
  including a scanner sending `http://remindly.care/wp-admin/install.php?step=1`
  *as its user agent*. It now has to look like a browser to be counted as one,
  and the denylist still runs first because bingbot advertises itself inside an
  otherwise complete Chrome user agent and would sail through an allowlist
  alone. Against the user agents actually observed in production this moves 17
  of 55 out of the human column. It does not — and cannot — see a scraper that
  sends a convincing browser user agent; separating those would need a
  per-visitor identifier, which is the one thing these pages refuse to store.
  Rows written before this change keep their old classification, because the
  user agent was never stored. The allowlist counts an iOS web view as a
  browser even when it carries no Safari token, because a link tapped inside
  the Facebook app is exactly how the traffic this measures arrives.
- **Production could not boot, and CI could not have known.** A deploy failed
  with `NameError: uninitialized constant MailDeliveryJob` — the container
  exited 1 and never became healthy. Kamal kept the previous version serving, so
  there was no outage, but nothing shipped.
  `config/initializers/postmark.rb` touched `ActionMailer::Base` during
  initialization, which fires the `on_load` hook and constantizes the configured
  `delivery_job` before autoloading can resolve a constant from `app/`. The
  initializer was pure duplication — `config/environments/production.rb` already
  sets both `delivery_method` and `postmark_settings` — so deleting it is the
  whole fix. It was also wrapped in `if Rails.env.production?`, meaning its
  contents ran in exactly one environment, and that environment was the one no
  test and no CI job had ever started: 407 green specs against an app that could
  not start. CI now boots the production environment on every PR, using
  `SECRET_KEY_BASE_DUMMY` so it needs no secrets.
- **The coverage gap email arrives in the morning, not at 4am.** Schedules in
  `config/recurring.yml` are UTC, because `config.time_zone` is left at its
  default — which is not obvious when writing "8am". This job emails a caregiver
  to say nobody is scheduled to look after their parent on an upcoming day, and
  at 8am UTC it landed at 4am Eastern and 1am Pacific, buried under overnight
  mail by the time anyone was awake to act on it. Now `0 12 * * *` — 8am Eastern
  in summer, 7am in winter. A new spec guards the whole file, because a mistake
  in it is silent by construction: a schedule that does not parse, or a class
  that does not exist, means the task simply never runs, which looks exactly like
  a feature nobody uses.
- **Stop mailing addresses that no longer exist.** `CheckCoverageGapsJob` mailed
  two demo accounts every morning from 24 July to 9 August — 44 failed jobs,
  every one a `Postmark::InactiveRecipientError`. Both addresses had hard
  bounced ("unknown user, mailbox not found"), after which Postmark marks an
  address inactive and refuses every later send. Nothing was broken in the job;
  it was told to email people who do not exist, and had nowhere to record that
  it had been refused, so it rediscovered the fact daily. The exposure was real:
  aiming mail at mailboxes that are not there is what erodes a sending
  reputation, and every message now leaves the same address that carries
  magic-link logins — so the eventual cost of ignoring it is that nobody can log
  in. Delivery failures Postmark declares permanent are now discarded rather
  than retried (its own `retry?` says so), the address is recorded on the user,
  and notification mail skips it thereafter. In-app notifications are
  deliberately still created: a dead mailbox is no reason to hide a coverage gap
  from someone inside the app.
- **Public pages no longer record analytics visits.** `/faq`,
  `/routine_sheet`, `/blog` and every post were logging an IP, referrer and
  device for each anonymous reader while the privacy policy said public pages
  were not tracked. The exclusion now derives from the same list the sitemap is
  built from, so a page is public in both places or in neither.
- **The privacy policy discloses the mailing list** — what is stored, what it is
  used for, that Postmark sees it, and how to come off it.
- **Signing up twice no longer 500s.** Two concurrent requests for the same
  address could both pass the lookup before either committed.
- **The welcome email's replies reach a person.** It asks people to reply in
  order to stop, and was sending from an unmonitored `noreply@` address.
- **Tables in blog posts render properly** — cells had no padding and ran into
  one another.
- **Printing the routine sheet keeps its full-size handwriting rows.** Print
  density rules added for the checklist were global and shrank them from 2.6rem
  to 1.8rem — smaller boxes to write in, on a sheet made to be written on.
- **The blog is called "Blog" and the FAQ is called "FAQ"** rather than "Writing"
  and "Questions", both of which were chosen for tone at the cost of being
  scannable — people look for the word they expect, and the FAQ page's own title
  already used the conventional one.
- **`/blog` has a title worth showing in a search result** — it was "Writing",
  eighteen characters with no indication of what the writing is about.

## [0.5.0] - 2026-07-19

### Added
- **Marketing homepage at `/`**: the site had no indexable homepage — `/` was
  `dashboard#index` behind `authenticate!`, so it redirected to `/login` and
  Search Console reported it as "Page with redirect". Logged-out visitors now
  get a marketing page; signed-in users still go straight to `/dashboard`. It
  uses its own layout with inlined CSS, so it loads no third-party assets and
  sets no session cookie. It also links `/how_to`, which nothing linked to
  before.
- **Tap-to-start overlay when voice is locked**: browsers refuse
  `speechSynthesis` until the user has interacted with the page, and on iOS that
  applies after every load — including reloads iOS performs on its own. A page
  that cannot speak looked identical to one with nothing to say. The overlay
  makes the requirement explicit and is skipped for anyone who has turned voice
  announcements off.
- **`PruneAnalyticsJob`**: 90-day retention for Ahoy visits and events, nightly.
  `visitor_duration` only governed the cookie, so nothing removed the rows and
  the oldest visit in production held an IP address 270 days old. Undated rows
  count as expired, since a row with no timestamp can never be shown to be
  recent.
- **CI that actually runs**: tests, Brakeman and RuboCop on every PR. The
  workflow had lived at `backend/.github/workflows/ci.yml`, a directory GitHub
  Actions never reads, so no pull request in this repository had ever reported a
  check.

### Changed
- **Retired the standalone voice client**: three copies of the voice logic
  existed (`clients/web/`, `backend/public/client/`, and
  `backend/public/voice_reminders.js`). Only the last is reachable by seniors,
  and the duplication caused a day of voice fixes to land in a client nobody
  used. `/client/*` now redirects, carrying legacy magic-link tokens through to
  `/login/verify` so links in already-sent emails keep working.
- **Public pages no longer identify anonymous readers**: `/` and `/how_to`
  record no analytics visit and leave no tracking cookie. Everything behind the
  login still tracks. `visitor_duration` drops from 2 years to 30 days.
- **Cleared 604 RuboCop offenses** and enabled the lint job, so the rule holds
  from here rather than drifting.
- README, CLAUDE.md and the deployment guide rewritten: they described
  `clients/web` on port 8080 as the senior interface, which is not what is
  deployed and cost a day of work aimed at the wrong client.

### Fixed
- **Seniors could not acknowledge reminders**: `AcknowledgementsController`
  inherited from `WebController`, whose CSRF check rejected the voice client's
  Bearer request with 422 before it reached the database. Moving to
  `ApplicationController` then broke the session-authenticated page instead. It
  now accepts either credential, with CSRF skipped only for the Bearer scheme.
- **Voice announcements failed silently on desktop**: unlock was gated on
  `isIOSDevice()`, but Chrome's autoplay policy refuses speech on any untouched
  page. Voice now starts locked everywhere, and a refused announcement is queued
  and spoken once the user interacts rather than being lost — it was marked
  delivered before `speak()` was called.
- **Snooze could move a reminder earlier**: the delay was measured from `now`
  regardless of when the reminder was due, so snoozing a 10:25 reminder at 10:00
  rescheduled it to 10:10. It is now measured from the later of the scheduled
  time and now, and is idempotent on retry.
- **Snooze is hidden until a reminder is due**, and the highlight is reserved
  for reminders that are actually due rather than applied to every card.
- **The dashboard nav was invisible on phones**: it was `hidden sm:flex` with no
  mobile menu, so a senior on a phone saw only Profile and Sign Out and could
  not reach their own reminders page.
- **Canonical URLs** across `remindly.anakhsoft.com`, `remindly.care` and
  `www.remindly.care`, resolving the duplicate-content report that prompted this
  work.
- The pending-approval screen said "contact an administrator" without naming
  one, leaving new users with no way to get their account enabled.

### Security
- **Internal documentation is no longer served from `public/`**: six files,
  roughly 1,100 lines of architecture and integration detail, were publicly
  readable. A spec now fails if any Markdown or dependency manifest reappears
  there.
- **The post-login redirect takes a destination from an allowlist**, not a URL,
  so a genuine Remindly login link cannot be crafted to deliver a signed-in user
  to somewhere else.


## [0.4.3] - 2026-05-03

### Fixed
- **Restore environment config clobbered by Rails 8.1 `app:update`**: The
  Rails 8.1 upgrade replaced `config/environments/production.rb` and
  `development.rb` with template defaults and dropped the project's
  customizations. Re-applied them:
  - Production: `assume_ssl` / `force_ssl` (HSTS + secure cookies),
    `solid_cache_store`, Solid Queue Active Job adapter (so `deliver_later`
    and `CheckCoverageGapsJob` work), Postmark delivery method,
    `raise_delivery_errors`, mailer host / from, `host_authorization` `/up`
    exclude, and the explicit hosts allowlist for `remindly.anakhsoft.com`,
    `remindly.care`, and `www.remindly.care`.
  - Development: `letter_opener` delivery method and mailer host port `5000`
    so dev magic-link emails open in the browser again.
- Drop the `bin/importmap audit` step from `config/ci.rb` since
  `importmap-rails` is not a dependency.


## [0.4.2] - 2026-05-03

### Fixed
- **Magic link host matches login origin**: Magic-link emails now point at the
  domain the user actually started from. Previously, a login begun on
  `remindly.care` emailed a `remindly.anakhsoft.com` link because the URL was
  always built from the configured `base_url`. Both `MagicController#request_link`
  (voice web client) and `SessionsController#request_magic_link` (caregiver
  dashboard) now pass `request.base_url` to the mailer, validated against an
  allowlist of known hosts; off-list hosts fall back to the configured `base_url`.


## [0.4.1] - 2026-04-03

### Added
- **Caregiver Invitation Emails**: Email notifications when caregivers invite other caregivers
  - Professional HTML and text email templates
  - Includes inviter name, senior name, and login link
  - Lists caregiver permissions and capabilities
  - Sent asynchronously via background job
  - Comprehensive test coverage for mailer


## [0.4.0] - 2026-01-09

### Added
- **Recurring Tasks**: Full support for recurring tasks with user-friendly UI
  - Daily, weekly, and monthly recurrence patterns
  - Visual pattern builder with live preview
  - Auto-generates RRULE in iCalendar format
  - Automatically expands into task instances for next 30 days
  - Parent-child relationship (template → instances)
  - Edit template to regenerate all future instances
  - Reuses existing Recurrence service from Reminders
  
- **Open-Ended Tasks**: Tasks without specific scheduled dates
  - Easy checkbox toggle: "Make this an open-ended task"
  - Auto-hides date field when marked as open-ended
  - Smart default (tomorrow at 9 AM) when converting to scheduled
  - Purple badge display throughout UI
  - Separate section on tasks index showing open-ended tasks
  - Filter option to view all open-ended tasks
  - Caregivers can claim when available
  
- **Blocking Unavailable Times**: Prevent task scheduling during unavailable periods
  - Create time blocks with start/end times and optional reason
  - Recurring patterns: Daily, Weekdays, Weekends, Weekly, Every Night
  - One-time blocks for specific dates/times
  - Active/inactive toggle to temporarily disable blocks
  - Automatic validation prevents task scheduling during blocked times
  - Overlap prevention for time blocks
  - Detailed error messages showing conflict details
  - Full CRUD interface for managing time blocks
  
- Database migrations:
  - Added `rrule`, `tz`, `start_time`, `parent_task_id` to tasks table
  - Made `scheduled_at` nullable in tasks table
  - Created `time_blocks` table with full recurrence support

### Changed
- Task model now supports optional `scheduled_at` for open-ended tasks
- Task form includes recurrence pattern builder with dropdown selectors
- Task validation now checks against blocked time periods
- Tasks index page reorganized with open-ended tasks section
- Added "🚫 Blocked Times" button to tasks navigation

### Fixed
- All views now handle nil `scheduled_at` values correctly
- Task assignment notifications work with open-ended tasks
- Senior dashboard displays open-ended tasks without errors
- Task show view handles tasks without scheduled dates

### Security
- Time block access restricted to senior and their caregivers
- Validation prevents overlapping time blocks for security


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
