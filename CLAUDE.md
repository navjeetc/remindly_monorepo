# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Remindly is a desktop-first, caregiver-aware reminder system for seniors. The monorepo contains:
- **`backend/`** — Rails 8 API (Ruby 3.3.5, SQLite3, JWT magic-link auth, IceCube recurrence)
- **`clients/macos-swiftui/`** — SwiftUI macOS app (Xcode project)
- **`shared/locales/`** — i18n translation files

## Commands

### Setup
```bash
make backend-setup          # bundle install + db:create + db:migrate
```

### Running
```bash
./start_backend.sh          # Backend on http://localhost:5000
make dev                    # Rails serves the dashboard and the voice client
```

### Testing & Linting
```bash
make rspec                                    # Run all backend specs
cd backend && bundle exec rspec spec/path/to/spec.rb  # Run single spec file
cd backend && bin/brakeman --no-pager         # Security scan (run in CI)
cd backend && bundle exec rubocop             # Linting (CI runs bin/rubocop -f github)
```

### Database
```bash
make backend-db             # Drop, recreate, and migrate DB
cd backend && bin/rails db:migrate
cd backend && bin/rails db:seed
```

### Deployment
```bash
./deploy.sh                 # Kamal deploy to DigitalOcean (prod)
```

## Architecture

### Authentication
Magic-link email flow — no passwords. Users request a token via `GET /magic/request?email=X`, click the emailed link, and exchange the token for a JWT via `POST /magic/verify`. The JWT is stored in localStorage (web) or Keychain (macOS). Dev shortcut: `GET /magic/dev_exchange?email=X`.

### Recurrence
Reminders and tasks use iCalendar RRULE format stored in the DB. `app/services/recurrence.rb` uses the `ice_cube` gem to expand RRULEs into concrete `occurrences` records. Occurrences drive the daily reminder display.

### Data Model
- **User** — can be a senior, caregiver, or both; linked via `CaregiverLink`
- **Reminder** → **Occurrence** → **Acknowledgement** — core reminder loop (legacy, still used by web client)
- **Task** — newer primary model; supports recurring templates (`rrule`), open-ended tasks (no date), and external sync from scheduling integrations
- **TimeBlock** — senior unavailability periods; also supports RRULE recurrence
- **SchedulingIntegration** — caregiver's external calendar (Acuity); syncs appointments as Tasks

### Background Jobs (Solid Queue)
Configured in `config/recurring.yml`. `CheckCoverageGapsJob` runs daily at 8am to detect caregiver coverage holes and send notifications.

### Rails Server Configuration
Backend runs on port 5000 (not the default 3000). CORS is enabled via `rack-cors` for cross-origin clients. `JWT_SECRET` env var is required at runtime (defaults to `please_change_me` in dev).

Note on macOS: the AirPlay Receiver (`ControlCenter`) squats on port 5000 when it is enabled, so `rails server -p 5000` may lose the bind. Either turn AirPlay Receiver off in System Settings → General → AirDrop & Handoff, or run on another port.

### Public marketing site
Everything a logged-out stranger can reach is served by `PagesController`, `PostsController` and `SubscribersController`, all of which include the `PublicPage` concern. That concern is what guarantees the two properties the request specs assert on every one of these pages:

- **The `marketing` layout, not `dashboard`** — the dashboard layout pulls Tailwind from a CDN (~400KB of JS). The marketing layout inlines its CSS and loads nothing third-party, because these are the pages search engines index.
- **No cookies for anonymous visitors** — Ahoy's cookies are dropped, and the layout deliberately omits `csrf_meta_tags` so no session cookie is issued either. Adding a `form_with` to any of these pages breaks that, which is why the mailing-list form is a plain `form_tag` and `SubscribersController` skips forgery protection (see the comment there for why that is safe on that specific endpoint).

Pages: `/` `/how_to` `/faq` `/routine_sheet` `/blog` `/privacy` `/terms`. `PagesController::STATIC_PATHS` is the authoritative list — `robots.txt` disallows everything else, and `/sitemap.xml` is rendered from that constant plus the posts on disk.

`ApplicationHelper::CANONICAL_HOST` exists because the app answers on three hostnames (`remindly.anakhsoft.com`, `remindly.care`, `www.remindly.care`). Canonical tags, `og:image` and sitemap entries all pin to one of them.

Mailing-list subscribers are mirrored into **GoHighLevel**, where campaigns are sent (off Postmark, which carries the sign-in links). `Subscriber` callbacks enqueue `SyncSubscriberToCrmJob`, which calls `GoHighLevel` (`app/services/go_high_level.rb`). The GHL sub-account is shared with other businesses and Remindly's contacts are told apart **only by their `remindly-*` tags**, so that class must never pass tags to upsert (they replace a contact's existing tags) or overwrite another business's fields. Unsubscribing deletes the contact only when it is purely Remindly's (our source, only `remindly-*` tags); otherwise it removes Remindly's tags. The privacy policy promises the address is deleted on unsubscribe and discloses it as "our CRM" (deliberately not naming GoHighLevel), so keep the two in step. The job takes only an email and applies whether that address is on the list *when it runs* (one job per address at a time), so a late or retried job can never put back someone who unsubscribed. It is a no-op until `go_high_level.token` and `go_high_level.location_id` are in credentials; after adding them, run `bin/rails subscribers:sync_to_crm` once.

### Blog
Posts are Markdown files in `backend/content/posts`, parsed by `Post` (a plain model, no database table) — see the class comment for why files rather than a table. Publishing is adding a file with `title`, `description` and `published_on` front matter; the index, sitemap and Article structured data all pick it up with nothing else edited. **A `published_on` in the future is a draft** and stays out of both the index and the sitemap. Malformed front matter raises at load rather than rendering a post with a blank heading.

Post bodies are rendered with `html_safe` — sound only because posts are repo files reviewed in a PR. If posts ever come from anywhere else, sanitize first.

`docs/MARKETING_PLAN.md` sets out what this is all for.

`docs/ONBOARDING_FEATURES.md` is the feature list pasted into invitation emails for new users. It lists only what is live in production, and it is a pitch rather than a changelog: a PR that ships something worth telling a prospective user about adds it, a PR that makes an entry wrong corrects it, and a PR that deliberately leaves it alone says so.

### UI conventions
**Read `docs/UI_STYLE_GUIDE.md` before adding or changing any field, button or form on a web page.** Fields use the `field` class, buttons use `button` plus `button-primary`, `button-secondary` or `button-danger` (filled, never a white outlined box), new-record forms autofocus the first field a person types into, and labels carry no emoji. The styles live in `backend/app/views/shared/_ui_styles.css.erb`; `spec/requests/form_fields_look_like_fields_spec.rb` enforces the rules across every view, so a page that skips them fails CI.

### Clients
- **Voice client for seniors** is `/voice_reminders` — a Rails page whose announcements are driven by `backend/public/voice_reminders.js`. It authenticates with the Rails **session**, not a Bearer token, and is linked from the dashboard nav. A standalone JS client at `clients/web/` (served at `/client/`) was superseded by this page and removed; `/client/` redirects to it.
- **macOS client** configures `APIClient.base` in Xcode; uses `AVSpeechSynthesizer` for TTS

### Deployment
After deploying, run `docs/POST_DEPLOY_CHECKS.md` — a short list of things that pass in CI and still fail in production. Every item on it is a failure this project has actually had (Solid Queue not running, a mailer sending from a domain Postmark rejects, public pages recording IPs while the privacy policy said they did not).

Kamal + Docker targeting a single DigitalOcean server (`161.35.104.56`). SQLite3 persists on a Docker volume at `/rails/storage/production.sqlite3`. The Docker entrypoint runs migrations automatically on deploy. SSL via Let's Encrypt at `remindly.anakhsoft.com`. Secrets (`KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`) live in `.kamal/secrets`.

### CI (GitHub Actions)
Three jobs on PRs and pushes to `main`, defined in `.github/workflows/ci.yml`:
- **`test`** — runs the full RSpec suite, including the guard specs that enforce repo invariants (`web_client_sync_spec.rb` for client drift, `public_assets_spec.rb` for files served from `public/`)
- **`scan_ruby`** — Brakeman security scan
- **`lint`** — `bin/rubocop -f github`

The workflow **must stay at the repository root**. It previously lived at `backend/.github/workflows/ci.yml`, where GitHub Actions never reads, so it had never run — no PR reported a check until 2026-07-18.

The `lint` job is green and expected to stay that way: the backlog of ~604 offenses was autocorrected before the job was enabled. Run `bundle exec rubocop` on the files you touch before pushing — style drifts silently otherwise. Note `bin/rubocop` may fail to load outside `bundle exec` depending on the local Ruby setup.

`bin/brakeman` prepends `--ensure-latest`, so the scan fails when the gem falls behind the latest release — update the gem rather than removing the flag.

## Key Environment Variables

| Variable | Purpose |
|----------|---------|
| `JWT_SECRET` | HMAC secret for JWT signing (required) |
| `RAILS_MASTER_KEY` | Rails credentials decryption (production) |
| `ENABLE_NATIVE_SCHEDULING` | Feature flag for caregiver availability module |
