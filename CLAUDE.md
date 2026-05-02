# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Remindly is a desktop-first, caregiver-aware reminder system for seniors. The monorepo contains:
- **`backend/`** — Rails 8 API (Ruby 3.3.5, SQLite3, JWT magic-link auth, IceCube recurrence)
- **`clients/web/`** — Vanilla JS/HTML voice reminder interface for seniors (no framework)
- **`clients/macos-swiftui/`** — SwiftUI macOS app (Xcode project)
- **`shared/locales/`** — i18n translation files

## Commands

### Setup
```bash
make backend-setup          # bundle install + db:create + db:migrate
cd clients/web && npm install
```

### Running
```bash
./start_backend.sh          # Backend on http://localhost:5000
cd clients/web && npm run dev  # Web client on http://localhost:8080
make dev                    # Both via tmux (requires tmux)
```

### Testing & Linting
```bash
make rspec                                    # Run all backend specs
cd backend && bundle exec rspec spec/path/to/spec.rb  # Run single spec file
cd backend && bin/brakeman --no-pager         # Security scan (run in CI)
cd backend && bin/rubocop -f github           # Linting (run in CI)
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

### Clients
- **Web client** talks to Rails REST API; `apiBaseUrl` is configurable via localStorage (defaults to `localhost:5000` or current domain origin)
- **macOS client** configures `APIClient.base` in Xcode; uses `AVSpeechSynthesizer` for TTS

### Deployment
Kamal + Docker targeting a single DigitalOcean server (`161.35.104.56`). SQLite3 persists on a Docker volume at `/rails/storage/production.sqlite3`. The Docker entrypoint runs migrations automatically on deploy. SSL via Let's Encrypt at `remindly.anakhsoft.com`. Secrets (`KAMAL_REGISTRY_PASSWORD`, `RAILS_MASTER_KEY`) live in `.kamal/secrets`.

### CI (GitHub Actions)
Two jobs on PRs and pushes to `main`: Brakeman security scan and Rubocop lint. Tests are not run in CI (run locally with `make rspec`).

## Key Environment Variables

| Variable | Purpose |
|----------|---------|
| `JWT_SECRET` | HMAC secret for JWT signing (required) |
| `RAILS_MASTER_KEY` | Rails credentials decryption (production) |
| `ENABLE_NATIVE_SCHEDULING` | Feature flag for caregiver availability module |
