# Design: reminder links — hearing your reminders without signing in

Status: **proposed**, not built. Written 2026-07-27.

## The problem

A senior's session lasts 30 days (`sessions_controller.rb`, `exp: 30.days.from_now`).
So roughly once a month, someone who by definition finds technology difficult has
to get into their email, find a message, and click a link — or they stop hearing
their medication reminders.

It fails in the worst possible way, too: silently. Nothing announces that the
session expired. The tablet just sits there, showing a login page nobody reads,
and the first anyone knows is when a caregiver notices the acknowledgements
stopped — or doesn't.

The same problem recurs whenever the tab closes, the device restarts, or the
browser clears cookies.

## What this proposes

A permanent, unguessable URL per senior — `/r/<token>` — that leads straight to
their voice reminders page with no sign-in. The caregiver sets it up once,
bookmarks it or adds it to the home screen, and the senior never sees a login
screen again.

This is a **capability URL**: the secret in the address *is* the credential.
Same pattern as a calendar `.ics` feed or a "anyone with the link" document.

## What does not change

**The signed-in experience is untouched.** Everything that works today keeps
working exactly as it does. A senior who signs in normally gets the full app.

The link grants a deliberately small subset:

| Capability | Signed in | Reminder link |
|---|---|---|
| Hear today's reminders spoken aloud | yes | **yes** |
| See today's reminders on screen | yes | **yes** |
| Mark a reminder done | yes | **yes** (see phasing) |
| Snooze a reminder | yes | **yes** (see phasing) |
| Dashboard | yes | no |
| Profile — name, timezone, role | yes | no |
| Generate a pairing code | yes | no |
| Remove a caregiver's access | yes | no |
| See tasks or coverage | yes | no |
| Notifications page | yes | no |
| Create or edit reminders | yes (caregiver) | no |

## The central safety property: default deny

The obvious implementation — have the token log the senior in — is wrong. It
would hand anyone with the URL the full dashboard, including the ability to
unlink caregivers. Worse, every controller added in future would silently become
reachable by link.

So the two must be separate concepts that never merge:

- **`current_user`** — a real session. Unchanged. Every existing controller keeps
  using it and keeps behaving identically.
- **`reminder_link_user`** — the senior identified by a link token. Referenced by
  exactly two places: the voice reminders page and acknowledgement creation.

Nothing else in the app ever looks at `reminder_link_user`. A controller written
next year is unreachable by link **because it does not mention it** — not because
someone remembered to block it. That is the property worth paying for: safety by
construction rather than by vigilance.

`authenticate!` stays as it is and continues to reject link visitors, so
forgetting to opt a controller in fails closed.

## Threat model

The instinct is that a no-login URL to medication information is alarming. That
framing does not survive contact with the actual deployment.

**The information is already ambient.** The product is a tablet on a kitchen
table with the screen on, continuously displaying "Take your morning medication —
two white tablets with breakfast." Family, visiting carers, neighbours can all
already read it. A secret URL on that same device adds very little to what the
room already exposes.

The real risk is the **URL escaping the device**. That is what to design against.

### Leak vector 1: the referrer header (most important)

`voice_reminders` currently loads `https://cdn.tailwindcss.com`. Every page load
sends a `Referer` header to that CDN containing the full URL. Put a token in the
path and every senior's permanent credential is shipped to a third party and
recorded in their logs.

Two fixes, and the second is better:

1. `Referrer-Policy: no-referrer` on the page.
2. **Give the voice page its own light layout with inlined CSS**, dropping the CDN
   entirely.

Option 2 solves three problems at once: no referrer leak, no third-party request,
and a much lighter page for the old tablet this runs on. The marketing layout
already does exactly this for related reasons and is a good model.

### Leak vector 2: logs

The token must not reach application logs, request logs, or error reports. Add it
to `config.filter_parameters` and prefer the exchange flow below, which removes
the token from the URL after first use.

### Leak vector 3: crawlers

`robots.txt` disallow on `/r/`, plus `noindex`. A link that ends up in a search
index is a link that ends up everywhere.

### Leak vector 4: the link being shared

Unavoidable, and the reason revocation is a first-class feature rather than an
afterthought.

### What a leaked link actually costs

Read access to one senior's reminder titles and times — much of which is already
visible in their kitchen — **plus the ability to mark a dose as taken**.

That second one deserves attention. A false "taken" tells the caregiver the
medication was swallowed when it was not. That signal is the entire reason the
product exists. It is not a catastrophic risk, but it is the one that argues
hardest for easy revocation and visible "last used" information.

## Mechanics

### Model

`ReminderLink`
- `user` — the senior
- `token` — `SecureRandom.urlsafe_base64(32)`, unique index, matching the
  existing `CaregiverLink.generate_pairing_token` precedent
- `revoked_at` — nullable; revoked links 404 like any unknown token
- `last_used_at` — so a caregiver can see whether a link is live or stale
- `label` — optional, e.g. "kitchen tablet", if per-device links are chosen

### Flow

1. `GET /r/<token>` looks up a live link, sets a long-lived signed cookie
   identifying the senior in **link mode**, touches `last_used_at`, and redirects
   to `/voice_reminders`.
2. The token is now out of the address bar and out of browser history going
   forward, and no longer appears in referrers.
3. The bookmark still points at `/r/<token>`, so clearing cookies or resetting the
   device recovers by itself.

That last point is the real advantage over simply extending the session to a
year: **a bookmarked capability URL survives cookie loss; a long session does
not.**

### Acknowledgements

`AcknowledgementsController` already carries a comment explaining that it juggles
two auth schemes and that fixing one previously broke the other. This adds a
third, and is the most delicate part of the work.

It must accept link mode **without** weakening the existing two, and the
occurrence lookup must stay scoped to the link's senior so a link can never
acknowledge anyone else's reminder.

### CSRF

Link mode still gets a session cookie, so the existing forgery protection
continues to apply to acknowledgement posts. No skip is needed — do not copy the
pattern from `SubscribersController`, which skips CSRF for reasons that do not
apply here.

### Rate limiting

Guessing a 256-bit token is not a real threat, but rate-limit `/r/:token` anyway
so enumeration attempts do not fill the logs. Rails 8's `rate_limit` is already
used in `SubscribersController`.

## Caregiver experience

The setup flow is where this feature succeeds or fails.

- Generate a link from the senior's page on the caregiver dashboard
- Show a **QR code** — setup becomes "point the tablet's camera at my phone"
  rather than typing 43 random characters
- Show `last_used_at` in plain words: "last heard from 2 hours ago", or
  "never used" — which is how a caregiver notices setup silently failed
- Revoke, and regenerate, with a plain-language warning that the old bookmark
  stops working
- Print-friendly, since some of this gets set up in person

## Privacy policy

A new access mechanism to health-related data needs disclosing, the same as the
mailing list did: that a link exists, what it grants, that it does not expire,
and how to revoke it. Bump the "last updated" date, which the policy itself
promises.

## Open decisions

1. **Who can revoke?** A senior can already remove a caregiver's access. Should
   they be able to kill their own link, or only caregivers? Leaning: both, since
   the senior owning their own access is a principle the app already holds.
2. **One link per senior, or one per device?** Per-device costs a little setup and
   buys precise revocation — "the old tablet we gave away". Leaning: start with
   one per senior, add labels later if it is wanted.
3. **Any expiry?** Leaning strongly no. Expiry reintroduces the exact failure this
   removes. `last_used_at` gives visibility without a deadline.
4. **Should the senior see they are in link mode?** Something quiet, so a
   caregiver can tell at a glance which mode a device is in.

## Phasing

**Phase 1 — read-only.** Hear and see reminders; no acknowledgement. Proves the
setup flow, the QR code, the layout change, and the default-deny boundary, with
the smallest possible surface. A leaked link at this stage exposes only what the
kitchen already shows.

**Phase 2 — done and snooze.** Adds the write capability, the third auth scheme
in `AcknowledgementsController`, and makes revocation matter.

Phase 1 is worth shipping alone. It is genuinely useful, and watching a real
senior use it will change the design of phase 2.

## What the specs must assert

The whole feature is a security boundary, so the tests are the deliverable as
much as the code:

- A link **cannot** reach the dashboard, profile, pairing, caregiver removal,
  tasks, coverage, or notifications — enumerated explicitly, so a new route added
  later that forgets the boundary fails here
- A link can only see and acknowledge **its own senior's** occurrences
- A revoked link 404s, and so does an unknown one — indistinguishably
- The signed-in experience is unchanged: existing specs must pass untouched
- The voice page loads **no third-party assets**, mirroring the existing
  marketing-page assertion, since that is what stops the token leaking
- The token never appears in a rendered page after the redirect
