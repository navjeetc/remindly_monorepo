# Deployment Guide

Remindly deploys as a single Rails application: one container, one host. Rails
serves the caregiver dashboard, the voice client at `/voice_reminders`, and the
API. There is no separate frontend to build or deploy.

## Deploying

```bash
./deploy.sh
```

That runs `kamal deploy` from `backend/`, which builds an image from the current
**committed** state (Kamal clones the repo — uncommitted work is not included),
pushes it to the registry, boots a new container, health-checks it, and switches
traffic over. Migrations run automatically from the Docker entrypoint.

Deploy from `main` unless you intend otherwise, and check that `git status` is
clean first — a dirty tree is a sign that what you tested is not what ships.

## Verifying a deploy

```bash
curl -s https://remindly.anakhsoft.com/version          # expect the new version
curl -s -o /dev/null -w '%{http_code}\n' \
  https://remindly.anakhsoft.com/voice_reminders        # 302 -> login when logged out
```

`GET /version` is the quickest confirmation that the new image is live. If it
reports the old version, the deploy did not take effect — see below.

For a client-side change, confirm the served asset actually contains it rather
than trusting the version string:

```bash
curl -s https://remindly.anakhsoft.com/voice_reminders.js | grep -c 'someNewFunction'
```

Anything user-facing on the senior path is worth exercising in a browser as well:
sign in, let a reminder come due, confirm it announces, and confirm **Done**
clears the card. Server-side checks cannot tell you whether a session-
authenticated action works — only a real session can.

## Rollback

Kamal keeps the previous container:

```bash
cd backend
bundle exec kamal rollback
```

To undo a specific change instead, revert the commit and deploy again.

Do **not** remove the `/client/*` redirect as part of a rollback. It is
deliberate: it carries legacy magic-link tokens through to `/login/verify` and
sends old bookmarks to `/voice_reminders`. Removing it would 404 links that are
still valid.

## Troubleshooting

### The deploy seemed to work but nothing changed

Check `GET /version` first. If it is stale, the container did not switch —
re-run the deploy and watch for "First web container is healthy".

If the version is right but a client change is missing, it is a cached asset.
`voice_reminders.js` is requested with a cache-busting timestamp, so a hard
refresh (Cmd+Shift+R) should be enough.

### Voice announcements are silent

Usually not a deployment problem. Browsers refuse `speechSynthesis` until the
user has interacted with the page, and **on iOS that means one tap after every
page load**. See "Voice Announcements" in the root `README.md` for the full
behaviour and its limits.

Otherwise check the device is not muted or on silent, and look for a
`SpeechSynthesisErrorEvent` in the browser console.

### 404 or an unexpected redirect

`/voice_reminders` is a Rails view behind the session login, not a static file —
a logged-out request correctly returns 302 to `/login`. `/client/*` redirects by
design.

## Testing on a real device

The iOS voice path cannot be verified on desktop: a user-agent override
exercises the branch but not WebKit's actual gesture requirement. The dev server
binds to localhost by default, so to reach it from a phone:

```bash
make backend-up-lan     # binds 0.0.0.0 and prints the LAN URL
```

The dev-login button is hidden on non-localhost hosts, so sign in with a
magic-link URL rather than the button.

## Environment

Secrets live in `backend/.kamal/secrets` (`KAMAL_REGISTRY_PASSWORD`,
`RAILS_MASTER_KEY`). `JWT_SECRET` is required at runtime. SQLite persists on a
Docker volume at `/rails/storage/production.sqlite3`, so it survives deploys —
and is not backed up by the deploy process.

The app is served on three hosts: `remindly.anakhsoft.com`, `remindly.care`, and
`www.remindly.care`. Canonical URLs point at `www.remindly.care`.
