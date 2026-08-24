# Changelog

All notable changes to the Remindly project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- **The phone-calls kill switch did not cover the button that places a call.**
  `ENABLE_PHONE_CALL_REMINDERS` gated the scheduler and the delivery job, so
  scheduled calls were off — but a caregiver pressing "Call and ask" reached
  Telnyx regardless, and the panel offering it rendered unconditionally.
  Shipping the feature switched off would still have let anyone with manage
  permission telephone a real senior. Both endpoints now refuse while the flag
  is off, and the panel is hidden with them.
- **A verification call could be placed after 9pm, or leave a reservation that
  never rang.** `verify_phone` reserved the attempt and then asked about calling
  hours on a second reading of the clock, so a request straddling 21:00:00 could
  pass the model's guard at 20:59:59.9, create the row, and be refused at
  21:00:00.1 — dialling nothing while leaving a reservation that held the
  senior's line and spent one of the five daily attempts. The clock is now read
  once for the decision. It is then read once more immediately before the
  provider call, because consistency is not currency: reserving on a stale
  reading and dialling after the boundary would have placed a real call outside
  the legally enforced window. If the window does shut in between, the
  reservation is undone rather than banked: nothing was sent to the provider, so
  it costs the caregiver none of their five daily attempts.
- **A finished call kept blocking the senior's next one.** `completed_at` was
  only written when the hangup event found the outcome still `pending`, so a
  call where nobody pressed anything — the outcome having already been set to
  `no_response` by the gather — never recorded that it had ended. Harmless until
  the one-call-at-a-time guard started reading that column to decide whether a
  senior may be called again, at which point a call that finished twenty seconds
  ago went on occupying the line for five minutes. Completion is now recorded
  unconditionally; only the outcome stays conditional, so a hangup arriving
  after a keypress cannot overwrite what the senior said.

- **A senior could be telephoned twice at the same instant.** Found in a live
  test: a dose falling due at the same moment as another occurrence's retry
  placed two calls in the same second to the same phone. One was answered; the
  other talked to voicemail, having spent a daily slot on a call that could not
  possibly be picked up. Nothing prevented it — `MAX_CALLS_PER_DAY` bounds the
  day and `MAX_ATTEMPTS` bounds the occurrence, and neither bounds concurrency.
  A reservation is now refused while that senior has a call in progress; the
  skipped occurrence stays pending and the scheduler, which runs every minute,
  offers it again once the line is free. An attempt that never rang does not
  occupy the line, and one abandoned by a dead worker stops counting after five
  minutes rather than blocking the rest of the day.

- **A missed call left two identical messages on the voicemail.** Found in a
  live test, not by a reviewer: Telnyx re-speaks a `gather_using_speak` prompt
  when no digit is collected, and `maximum_tries` was never set, so it used its
  default. One `call.answered` event, one gather command from us, and two
  recordings sixty-one seconds apart against a ten-second timeout. It is now
  explicitly `1` — a repeat only helps someone who fumbled the first prompt, and
  costs another voicemail message every time nobody picks up, which is exactly
  what makes an automated caller feel like a robocall. The real answer is
  answering-machine detection, which the design document already requires
  ("voicemail is not delivery") and which is not built: a machine answering is
  currently recorded as an answered call that happened to collect no digit.

- **Reminder calls had no upper age limit.** The scheduler matched every
  pending occurrence ever scheduled, and occurrences do not age out on their
  own: `MarkMissedOccurrencesJob` sweeps only within its seven-day
  `MARK_LOOKBACK`, so anything unacknowledged for longer stays `pending` for
  good. One production account had accumulated thirty such rows over six months,
  the oldest from the previous November — switching the feature on would have
  telephoned about ten of them within a minute of each other, then ten more
  every day, indefinitely. `LOOKBACK` bounds it to two hours: enough to survive
  a queue backlog, short enough that nobody is rung at bedtime about a dose due
  at breakfast. A call is far more intrusive than the status write the missed
  sweep performs, so its window is deliberately much tighter.

- **The daily cap still was not a cap, and four more.** The slot number came
  from a moving `maximum` while the cap came from a separate `count`, which two
  workers defeat: both pass the count at nine, the first takes slot ten, the
  second then reads a maximum of ten and takes eleven. Nothing collides. There
  are now exactly `MAX_CALLS_PER_DAY` slots in a day and a reservation claims
  the lowest free one, so two racing reserves pick the same slot and the index
  refuses one; a slot is released when an attempt turns out never to have rung,
  so it can be reused rather than leaving a hole. A senior's timezone is
  editable and the day hangs off it, so changing zones handed back a fresh set
  of slots — the zone each attempt was filed under is now recorded, which
  catches that without refusing the ordinary morning call after a full evening.
  A `reserved` row whose worker died was reported to caregivers as "we tried to
  call and could not get through", when nothing had reached the provider. And
  cancelling an attempt while recording why were two separate writes, so a
  crash between them left a state nothing could repair.
- **The Ed25519 webhook signature path had no test at all.** It is the
  production verification mode for a public endpoint that writes
  acknowledgements, and every spec stubbed the public key to nil, so it never
  ran. A regression in the header names, the signed-message format or the base64
  decoding would have passed CI and surfaced only once signature mode was
  switched on — at which point every callback would be rejected and no reminder
  call could be acknowledged.

- **A fifth review round: seven more, one of them user-visible.** The missed
  email's subject handled two of the three no-call reasons, so
  `not_attempted_in_time` fell through to "hasn't marked it as done" while the
  body of the same message said "Remindly did not call" — the subject blaming
  the senior for a call that was never placed, which is the exact failure that
  reason exists to prevent. The per-senior daily cap was a count followed by an
  insert, which three Solid Queue worker threads can all pass at once; it is now
  a `(user_id, call_day, daily_sequence)` unique index, so two reserves
  computing the same slot cannot both win. That cap also counted attempts where
  the phone never rang, so ten failures early in the day silenced every later
  reminder even after the provider recovered. A `cancelled` attempt was
  classified as "we tried and could not get through". `suppress_call!` decided
  first-refusal with a read rather than a conditional update, so two callers
  could each write a different reason. The cancel branch recorded nothing, so a
  sweep that closed an occurrence mid-claim produced a caregiver email claiming
  a call was attempted. And the notifications migration built a unique index
  without collapsing duplicates first — harmless on today's data, but the
  entrypoint runs `db:prepare` at container start, so a raise there aborts the
  boot rather than surfacing in a test.

- **Four more, from a fourth review pass.** The dialling job trusted the
  scheduler's `WHERE` clause for the per-user opt-in, so a senior who switched
  voice reminders off — or a job invoked directly for someone who never opted in
  — was still called; the opt-in is now re-read at dial time, like the status
  and the calling hours already were. `MAX_ATTEMPTS` is per occurrence, so a
  senior with six reminders due could take eighteen calls without exceeding it;
  `MAX_CALLS_PER_DAY` bounds the person rather than the reminder, counted in
  their own day. Correlating a stray callback matched the most recent
  uncorrelated attempt, so a delayed callback from attempt 1 could attach to
  attempt 2 and silence its real call — `client_state` now carries the attempt
  number and the claim is a conditional update on that exact row. And a job held
  in the queue past the missed sweep's grace left no record at all, so the
  caregiver was told the senior ignored a call that was still waiting to be
  placed.

- **Four more ways a caregiver could be told the wrong thing.** An accepted call
  whose `call_control_id` failed to persist could never be correlated, so every
  callback asked for a retry until the provider gave up and the senior stayed
  connected to a call that never spoke — the event's `client_state` now names
  the occurrence, so the reserved attempt is adopted and the call proceeds. The
  scheduler skipped out-of-hours occurrences before `VoiceReminderJob` ever ran,
  so the suppression recording added for exactly this case never executed in
  production, where the scheduler is the only caller. `phone_failure_reason`
  consulted the senior's *current* preferences before the durable record, so
  switching voice reminders off after a failure retroactively turned a call
  nobody placed into a reminder she had ignored. And duplicate notification
  deliveries could race: the "already notified" check was a SELECT against an
  unindexable json column, so both workers passed it — `notifications` now has a
  real `occurrence_id` column with a partial unique index, and the insert
  decides rather than the check.

- **The caregiver email stated the wrong calling window.** `CALLING_HOURS` is
  the exclusive range `(8...21)`, and Ruby's `Range#last` returns the range's
  *end* regardless of exclusivity — so `last + 1 - 12` gave `10` and the mail
  read "between 8am and 10pm" while `within_calling_hours?` actually stops at
  9pm. `.max` respects exclusivity. The suppression log had the same fault,
  reading "8:00-22:00".
- **Four ways an event could be retired without being handled.** A gather that
  failed left the senior connected to silence with no retry, because
  `answered_at` was recorded first and suppressed redelivery; the gather now
  precedes the flag, and Telnyx's `command_id` makes a duplicate harmless. A
  callback arriving before `dial` wrote `call_control_id` back was answered
  `200` and lost for good; `client_state` now identifies our own calls so they
  can be retried, while genuinely foreign ids are still dropped rather than
  retried forever. The caregiver notification was conditioned on a value
  computed inside an already-committed transaction, so a failed enqueue could
  never be recovered by a redelivery; it is now enqueued on every delivery,
  which both the job and the delivery beneath it already tolerate. And a dose
  resolved from another client between the status check and the dial was still
  telephoned about — the status is re-read after the attempt is claimed.

- **An unanswered senior could be telephoned dozens of times.** The scheduler
  skipped occurrences called within the last two minutes, but every dial reused
  one `TelnyxCall` row per occurrence, so its `created_at` never moved past the
  first attempt and the window stopped excluding anything. Running every minute
  against an occurrence that stays `pending` for the full 60-minute miss grace,
  that is around fifty consecutive calls to someone who did not pick up — all
  inside legal hours, so the calling-hours guard could not help. Attempts are
  now one row each, capped at three and spaced five minutes apart, per the
  design document's "retries after a few minutes, twice at most, then stops".
- **Two runs could both dial the same dose.** Nothing was written before the
  provider was called, so a redelivered job or two overlapping scheduler runs
  each POSTed without being able to see the other. An attempt is now claimed
  first, and a unique index on `(occurrence_id, attempt_number)` decides the
  race in the database — the loser is told before it dials rather than after.
- **A failed keypress was reported to Telnyx as success.** The handlers rescued
  every error, logged it, and still answered `200`, so the provider considered
  the event delivered and never resent it. A transient write failure therefore
  discarded the senior's "1" for good: the occurrence stayed pending and the
  caregiver was later emailed that she had not marked it done. Failures now
  propagate and the endpoint answers `500` so Telnyx retries; every handler is
  idempotent, and there are specs for the redelivered case.

- **A call that could not be placed also said the senior hadn't marked it
  done.** The previous fix covered calls suppressed for calling hours, but not
  calls that were attempted and never reached the provider — a missing API key,
  the provider down. Those left the occurrence pending, the sweep marked it
  missed, and the caregiver was told their mother had not marked her dose done.
  This is the state production is in today, with no `telnyx:` credentials at
  all: enabling voice reminders there would have produced that email for every
  single reminder. `Occurrence#phone_failure_reason` now separates the two
  cases, and the mail says which — "Remindly tried to call Mom about Metformin
  and couldn't get through", with the attempt count and an admission that the
  fault is ours. An attempt only counts as a real call once it has a
  `call_control_id`, which is the provider's receipt; testing the attempt row's
  mere existence let a reservation that failed before the API call masquerade
  as a call that rang.
- **A reminder that was never called said the senior hadn't marked it done**:
  once calls are confined to 8am–9pm, a 6am dose for a senior whose only channel
  is the telephone is suppressed at 6:00, marked `missed` at 7:00 by the sweep,
  and emailed to the caregiver as "hasn't marked Metformin as done". Nobody was
  asked. Reporting a non-event as a lapse sends a caregiver looking for a
  failure that never happened, which is the opposite of what this mail exists
  for. That case now says "Remindly couldn't call Mom about Metformin", names
  the hour and the window, and states plainly that nothing was contacted so it
  implies nothing about what the senior did. It reverts to the ordinary wording
  the moment a call actually went out — a queue backlog delivering a 7:55 dose
  at 8:05 is a real attempt and an ordinary miss.

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
- **Consent to be telephoned, and the only thing that can grant it.** Phone
  reminders shipped inert because nothing in the app could set a number or opt
  anyone in — deliberately, since the obvious screen (a number field and a
  checkbox) would let one person arrange automated calls to another who had
  never agreed. A caregiver can now propose a number and ask its owner a
  question; that is the entire surface. `TelnyxWebhooksController#consent!` is
  the only thing that can *enable* calls — nothing else sets
  `call_reminders_enabled` to true — and its single input is a `1` pressed
  during a verification call. Several paths clear it: an opt-out, and a change
  of number. Pressing `9` stops calls
  immediately and permanently; pressing nothing is declined, which is neither
  consent nor an opt-out, because someone who said nothing has not said stop.
  Changing the number forgets what the old one agreed to. An opt-out survives a
  number change, so a caregiver cannot undo a senior's "stop" by editing a
  field. Verification calls are bounded separately at five per number per day,
  since they are excluded from the daily cap that otherwise limits how often a
  number can be rung.

- **Phone reminders are behind a feature flag, off by default.** Until now the
  only thing preventing calls in production was that no senior had
  `voice_reminders_enabled` and a phone number — two ordinary columns, which a
  single console command sets, and setting them is the only way to try the
  feature there. Calls would then begin within the minute, and stopping them
  would need a deploy. `FeatureFlag.enabled?(:phone_call_reminders)`
  (`ENABLE_PHONE_CALL_REMINDERS`, default false) is the outer of two locks: it
  says the code may run at all, while the senior's own columns say whether it
  runs for them. It is checked in `VoiceReminderSchedulerJob` so no work is
  enqueued, and again in `VoiceReminderJob` because that job is reachable from
  a console or a retry — a flag that only guards the gate is not a kill switch.

- **Reminder calls are confined to 8am–9pm in the called party's own
  timezone**: automated voice calls are regulated and the window belongs to the
  person answering, not the server. `User#within_calling_hours?` is checked in
  two places on purpose — the scheduler, so an occurrence due at 2am enqueues
  nothing rather than a job every minute until the missed sweep claims it, and
  `VoiceReminderJob` itself, because that job is reachable from a console or
  from a retry hours after the failure that caused it, and a call placed at 3am
  cannot be taken back. A timezone that cannot be resolved blocks the call
  instead of assuming daytime. It cannot catch a timezone that is wrong but
  valid — the UTC-12 profile bug resolved perfectly well — which is why
  verifying the number with a real person still matters.
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
  verification that a number reaches the person it is meant to, and no
  answering-machine detection — and no way for anyone to opt in, since nothing
  in the app sets `voice_reminders_enabled` or `phone`.
  `docs/PHONE_CALL_REMINDERS_DESIGN.md` sets out what has to exist first, and
  why the timezone fix from August is load-bearing here: a user silently moved
  to UTC-12 would be telephoned in the middle of the night. Calling hours *are*
  enforced — see the entry above — and the whole feature sits behind
  `ENABLE_PHONE_CALL_REMINDERS`, off by default, so the scheduled job returns
  immediately and nothing can be dialled.

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
