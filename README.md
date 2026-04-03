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

### Starting the Application

**Terminal 1 - Backend (Rails 8 API):**
```bash
# From repo root
./start_backend.sh
```
The backend will start on `http://localhost:5000`

**Terminal 2 - Web Client (Voice Reminders):**
```bash
cd clients/web
npm run dev
```
The web client will start on `http://localhost:8080`

### Accessing the Application

- **Caregiver Dashboard**: `http://localhost:5000/dashboard`
  - Quick dev login: `http://localhost:5000/dev_login`
  - Manage tasks, invite caregivers, view seniors
  
- **Voice Reminders (for Seniors)**: `http://localhost:8080`
  - Web-based voice announcement interface
  - Quick dev login button available

### Alternative: Start Both with tmux
```bash
make dev
```
This starts both backend and frontend in a split tmux session (requires tmux installed).

### First Time Setup

**Backend Setup:**
```bash
make backend-setup
```
This will install gems and set up the database.

**Web Client Setup:**
```bash
cd clients/web
npm install
```

### API Endpoints
- `POST /reminders` `{ title, notes?, rrule, tz, category? }`
- `GET /reminders/today`
- `POST /acknowledgements` `{ occurrence_id, kind: taken|snooze|skip }`
- Magic-link: `GET /magic/request?email=...`, `GET /magic/verify?token=...`, dev: `GET /magic/dev_exchange?email=...`

### macOS Client (SwiftUI)
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
