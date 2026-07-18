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

## Voice Announcements

**A tap or click is required before the voice client can speak.** Every browser
gates `speechSynthesis` behind a user gesture, so a page nobody has touched
cannot talk. This is a browser restriction — no web app can work around it.

| Platform | Behavior |
|---|---|
| **iOS (iPhone/iPad)** | Always locked on load. One tap is needed **every time**, including after any reload. |
| **Desktop** | Unlocks automatically if the page has had any prior interaction (`navigator.userActivation`). Only a freshly loaded, never-touched page stays locked. |

The tap can be **anywhere on the page** — there is no need to find the 🔊 button.
If a reminder comes due while voice is still locked, it is queued and spoken as
soon as the user interacts, even if its scheduled time has already passed.

### Known limitations

These are real gaps, not bugs to be surprised by:

- **A reload re-locks voice.** iOS discards background tabs on its own, so an
  unattended iPad can silently stop announcing until someone taps it. Nothing on
  screen indicates this. A "Tap to start" overlay would make the requirement
  explicit rather than invisible.
- **Overdue reminders are never announced.** `checkDueReminders()` only fires
  while a reminder is still in the future (within `gracePeriod`, default 30s).
  If the device sleeps, the tab is suspended, or the page reloads across that
  window, the reminder is skipped permanently — the card still displays, so the
  loss is invisible. A bounded overdue grace would turn silent loss into a late
  announcement.
- **The web client cannot announce in the background.** Only a native app can.

### Debugging the client

Verbose logging is off by default. To enable it:

```js
localStorage.setItem('debug', 'true'); location.reload();
```

Errors always log regardless of this flag.

### Testing on a real device

The iOS voice path cannot be verified on desktop — a user-agent override
exercises the branch but not WebKit's actual gesture requirement. To test on a
phone or tablet, the dev server must listen on the LAN (it binds to localhost by
default):

```bash
make backend-up-lan     # binds 0.0.0.0 and prints the LAN URL
```

The web client hides its dev-login button on non-localhost hosts, so log in with
a magic-link URL rather than the button.

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
