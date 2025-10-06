# Remindly Monorepo (MVP)

Desktop-first, caregiver-aware reminders for seniors. Rails 8 API + SwiftUI macOS client. Monorepo layout:

```
remindly/
  backend/            # Rails 8 API (JWT magic-link, IceCube recurrence)
  clients/
    macos-swiftui/    # SwiftUI app scaffold (big buttons, TTS)
    tauri/            # (optional later) Vue + Rust shell
  shared/
    locales/          # i18n files
  scripts/ci/         # CI helpers
  Makefile            # common dev tasks
```

## Quick Start

### 1) Backend (Rails 8 API)
```bash
# from repo root
make backend-setup
export JWT_SECRET=please_change_me
make backend-up
# in another shell: dev auth + ping
JWT=$(curl -s "http://localhost:3000/magic/dev_exchange?email=senior@example.com")
curl -H "Authorization: Bearer $JWT" http://localhost:3000/reminders/today
```

**Endpoints**
- `POST /reminders` `{ title, notes?, rrule, tz, category? }`
- `GET /reminders/today`
- `POST /acknowledgements` `{ occurrence_id, kind: taken|snooze|skip }`
- Magic-link: `GET /magic/request?email=...`, `GET /magic/verify?token=...`, dev: `GET /magic/dev_exchange?email=...`

### 2) macOS Client (SwiftUI)
Open `clients/macos-swiftui` in Xcode. Set your backend base URL in `APIClient.base`. Run the app, hit **Refresh**, and acknowledge reminders with big buttons. TTS uses `AVSpeechSynthesizer`.

### 3) Tests
```bash
make rspec
```

## Configuration
- `JWT_SECRET` (required): shared HMAC for JWT signing.
- Database: PostgreSQL (see `backend/config/database.yml` you will create via `rails new`).

## Notes
- Rails 8 compatible; recurrence powered by `ice_cube`.
- CORS is enabled via `rack-cors` for desktop clients.
- This is an MVP scaffold—harden auth, add mailer for magic links, and write more specs before production.

## Next Steps
- Add Hotwire caregiver dashboard.
- Implement real mailer for `/magic/request`.
- Add Windows client via Tauri.
