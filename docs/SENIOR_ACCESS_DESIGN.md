# Design: getting a senior set up, and keeping them hearing reminders

Status: **proposed**, not built.

Supersedes and absorbs two earlier documents, both of which are folded in here in
full:

- `REMINDER_LINKS_DESIGN.md` (2026-07-27) — signing-in-free access via `/r/<token>`
- `CAREGIVER_CREATED_SENIOR_DESIGN.md` (2026-08-09) — letting the caregiver do the setup

They were separate until it became clear that **each contained the answer to a
gap in the other**, and that neither can ship a working product alone. Merged
2026-08-09.

## The problem, which is really one problem

**Existing seniors get logged out, silently.** A session lasts 30 days
(`sessions_controller.rb`, `exp: 30.days.from_now`). So roughly once a month,
someone who by definition finds technology difficult has to get into their email,
find a message and click a link — or they stop hearing their medication
reminders. Nothing announces it. The tablet sits there showing a login page
nobody reads, and the first anyone knows is a caregiver noticing the
acknowledgements stopped, or not noticing. The same happens whenever the tab
closes, the device restarts, or cookies are cleared.

**New seniors cannot be set up by the person who wants to set them up.** The
homepage promises "You create the reminders." It cannot be done. The real path
is: the caregiver signs in; **the senior signs in on their own device with their
own email** and generates a pairing code (`dashboard_controller.rb:151`); the
caregiver enters it; only then can they create a reminder, because
`dashboard#senior` requires an existing `caregiver_link`. There is no route for a
caregiver to create a senior — `invite_caregiver` runs senior → caregiver and the
reverse does not exist.

Both are the same problem wearing different clothes: **the product asks the
person least able to do email things to do email things**, or nothing works.

### The evidence for the second one

A Facebook post on 2026-08-08 brought **17 people** to the site. Three clicked
past the homepage. **Nobody signed up.** The five homepage fixes from early-user
feedback had already shipped, so the obvious copy explanations were addressed.

That is not proof this is the cause — see "What would make this unnecessary" —
but it is the largest known obstacle sitting directly behind the signup button.

## What this proposes

1. A permanent, unguessable URL per senior — **`/r/<token>`** — leading straight
   to their voice reminders with no sign-in. Bookmark it once; no login screen
   again. This is a **capability URL**: the secret in the address *is* the
   credential, like a calendar `.ics` feed.
2. A **caregiver-created account**, so the senior's entire involvement becomes
   *open this and leave the page up*.
3. A **six-digit code exchange** at `/start`, which is how the URL reaches the
   device at all — and which turns out to be the missing piece in both designs.

## What does not change

**The signed-in experience is untouched.** A senior who signs in normally gets
the full app. The link grants a deliberately small subset:

| Capability | Signed in | Reminder link |
|---|---|---|
| Hear today's reminders spoken aloud | yes | **yes** |
| See today's reminders on screen | yes | **yes** |
| Mark a reminder done | yes | **yes** (phase 2) |
| Snooze a reminder | yes | **yes** (phase 2) |
| Dashboard | yes | no |
| Profile — name, timezone, role | yes | no |
| Generate a pairing code | yes | no |
| Remove a caregiver's access | yes | no (but see self-revocation) |
| See tasks or coverage | yes | no |
| Notifications page | yes | no |
| Create or edit reminders | yes (caregiver) | no |

## The central safety property: default deny

The obvious implementation — have the token log the senior in — is wrong. It
would hand anyone with the URL the full dashboard, including the ability to
unlink caregivers, and every controller added in future would silently become
reachable by link.

So the two must be separate concepts that never merge:

- **`current_user`** — a real session. Unchanged. Every existing controller keeps
  using it and behaves identically.
- **`reminder_link_user`** — the senior identified by a link token. Referenced by
  exactly two places: the voice reminders page and acknowledgement creation.

Nothing else ever looks at `reminder_link_user`. A controller written next year
is unreachable by link **because it does not mention it** — not because someone
remembered to block it. Safety by construction rather than by vigilance.
`authenticate!` stays as it is and continues to reject link visitors, so
forgetting to opt a controller in fails closed.

## What this is not allowed to become

Removing the pairing step is not merely removing friction.
`generate_pairing_token` is created **by the senior**, on their own account, and
`pair_with` grants access to whoever presents it. Consent is a structural
property today: access cannot exist unless the person receiving reminders acted.

A monitoring tool set up on someone without their knowledge is a recognised
pattern in elder abuse. The current design prevents it by accident. Any
replacement has to prevent it on purpose.

**The resolution: consent moves from "before setup" to "at first use". It does
not disappear.** Nothing is spoken, nothing is recorded, and the caregiver sees
no activity until the senior's device opens the link and someone chooses to
start. That moment is when they are told who set this up and can refuse.

## Invariants

Things that must be impossible, not merely discouraged.

1. **A caregiver-created account is always a new account**, never an attachment
   to an existing one. Auto-linking would hand over an existing person's
   history — reminders, acknowledgements, other caregivers — to whoever typed
   their address.
2. **This flow never asks for the senior's email address.** See below. This is
   what makes invariant 1 structural: with no address there is no lookup, so
   nothing to collide with and no way to ask the form whether somebody already
   uses Remindly.
3. **Nothing happens until the senior's device opens the link and starts.** No
   speech, no acknowledgements, nothing for the caregiver to look at.
4. **The senior can always refuse**, in one action, without signing in.
5. **The senior is told when any caregiver is added**, not only the first.
6. **A caregiver cannot create accounts in bulk.** Rate limited per caregiver.

## Do not ask for the senior's address

An earlier draft collected it "optionally" and said an address already in use
would quietly fall back to pairing. That cannot work: if the address exists, no
account can be created, so the caregiver cannot go on to write reminders — and a
flow that visibly stops in one case and continues in the other **is** the
enumeration oracle invariant 2 exists to prevent. Identical responses and "carry
on with setup" are not simultaneously satisfiable.

So drop the field. **A senior created this way has no email address at all.**

- We already decided not to email them, so the address had no use.
- No address means no lookup, no collision, no branch, no oracle.
- It matches the scene: someone setting up a tablet in their mother's kitchen
  should not need to know which of her three addresses she still reads.

Two consequences to design for:

- `User` validates `email` for presence and uniqueness. Link-only seniors need
  that relaxed, and must be **structurally unmailable** rather than merely
  unmailed — the `email_undeliverable_at` machinery added 2026-08-09 is the
  natural home.
- Such an account cannot be recovered and cannot sign in. If the senior later
  wants a real account, they add their own address themselves, which is the same
  consent step this design moved to first use, arriving when it is needed.

## Do not email the senior

The obvious hand-over is to email the parent a link. It should not be built, for
a reason that has already cost this project once.

Emailing an address the app has never verified means any signed-in user can send
mail from `hello@remindly.care` to an arbitrary address. Bounces and complaints
follow. Every message in this app — including magic links — leaves that domain,
so the end state of poor sender hygiene is that **nobody can log in**. See the
changelog entry *"Stop mailing addresses that no longer exist"*, where mailing
two non-existent addresses for sixteen days was worth a PR of its own.

The six-digit code below removes the reason to want this at all.

## Getting the link onto the device

Both original documents had this gap. One said the caregiver "gets a link and a
QR code"; the other described a device visiting `/r/<token>` and bookmarking it.
Neither said how 43 characters of `urlsafe_base64` reach a tablet.

The obvious answers fail:

- **Typing the URL** — 43 mixed-case characters, on a tablet keyboard, for
  someone whose eyesight is part of why you are setting this up.
- **QR code alone** — fine on a tablet with a camera and a scanner that behaves;
  useless on the kitchen desktop the FAQ explicitly supports.
- **Email** — ruled out above.

### Move a short code, not a long URL

The pattern every television app uses:

1. The caregiver's screen shows a **six-digit code**, plus a QR code as a
   shortcut for devices that can scan
2. On the senior's device, someone goes to **`remindly.care/start`** — short
   enough to type, and short enough to say
3. They type the six digits
4. The server exchanges the code for the durable capability and redirects to
   `/r/<token>`, which sets the signed cookie, drops the token out of the address
   bar, and lands on the voice page
5. Bookmark it or add to the home screen. The bookmark holds `/r/<token>`, so
   the "survives cookie loss" property below still holds

The QR encodes `/r/<token>` directly, so both routes converge.

### Why this is more than a convenience

**Six digits can be read down a telephone.** Remote setup needs no email at all:
you are at home, your mother is at hers, you talk her through typing
`remindly.care/start` and read her the numbers.

This is the one channel this audience is comfortable with. Every other remote
option asks an older person to find a message in an inbox and trust a link inside
it — the exact interaction they are told never to trust.

### What it costs

A six-digit code is guessable where a 256-bit token is not, so the exchange
endpoint carries the burden the capability URL does not:

- **Ten-minute expiry**, **single use**, bound to one `provisional` link
- **Hard rate limiting** on `/start`, per IP and per code — Rails 8's
  `rate_limit` is already used in `SubscribersController`
- **No enumeration signal**: a wrong code and an expired code must be
  indistinguishable
- Generated with `SecureRandom`, never `rand`

## The states a link moves through

`CaregiverLink#pending?` means `caregiver_id` is `nil`, while every caregiver
action authorises through `current_user.caregiver_links`. So leaving it unset
means the caregiver **cannot create reminders**, which is the point of the
feature — and setting it opens the activity routes **before the senior has
consented**, which breaks invariant 3.

The state must therefore be explicit rather than inferred from a null foreign
key. Three states, not two:

| State | Meaning | Caregiver may |
|---|---|---|
| `pending` | senior generated a token, no caregiver yet (**today, unchanged**) | nothing |
| `provisional` | caregiver created the account; senior has not started | create and edit reminders |
| `active` | the senior opened the link and chose to start | everything they can do today |

**Authorisation splits by state, not by whether data happens to exist.** Reminder
authoring accepts `provisional` or `active`; every activity, acknowledgement and
coverage view requires `active`. Invariant 3 then holds because the routes
refuse, not because there happens to be nothing to show — the difference between
a guarantee and a coincidence.

Refusal destroys the `provisional` link and the account, which is safe for the
same structural reason: a provisional account can only contain reminders the
caregiver typed.

## A capability may destroy itself

A reminder link **cannot** remove a caregiver's access. If it could, anyone
holding a leaked URL could cut a family off from a vulnerable person's care —
a denial-of-care attack, worse than the disclosure it would prevent.

But invariant 4 requires a senior who never signs in to be able to refuse. Both
cannot be true as stated.

The resolution is narrow: **the link may destroy itself.** "Stop this" revokes
the token and the `provisional` link — the thing the caregiver set up stops
existing. It does not reach into account management, does not remove established
caregivers, and cannot be used against a senior already set up, because a revoked
token 404s like any unknown one.

Full caregiver management continues to require a real sign-in. A capability that
can end itself is not the same as one that can act on the account, and only the
first is needed here.

## Acknowledgements — the delicate part

`AcknowledgementsController` already juggles two auth schemes, and its header
comment records that fixing one previously broke the other:

```
/voice_reminders   Rails page, session cookie + CSRF token
/client/           Bearer <jwt>, no CSRF token
```

Link mode is a third. It must be accepted **without** weakening the other two,
and the occurrence lookup must stay scoped to the link's senior so a link can
never acknowledge anyone else's reminder.

**Persistence does not change.** The controller writes an `Acknowledgement` row
and flips `Occurrence.status` by compare-and-swap inside one transaction —
idempotent, and it hands off cleanly with the missed sweep. Link mode changes
*who is authorised to act*, not what is written. No new model, no new storage.

**CSRF needs no skip.** Link mode still gets a signed session cookie, so existing
forgery protection applies. Do not copy the pattern from `SubscribersController`,
which skips CSRF for reasons that do not apply here.

### Why a caregiver-created senior cannot live on phase 1

This is the interaction that forced the merge, and neither document stated it.

Phase 1 below is **read-only** — hear and see, no acknowledgement. That is fine
for an existing senior, who can still sign in normally when they want to mark
something done.

A **caregiver-created** senior has no email address, so they can never sign in.
Link mode is their *only* mode. If link mode cannot acknowledge, that senior can
never mark anything done, ever — so no acknowledgements, so no missed-dose
emails, so the caregiver gets nothing back. Which is the entire product: *"You
see what was marked done, and what wasn't."*

**Caregiver-creation therefore depends on phase 2, not merely on links
existing.** Shipping phase 1 and assuming caregiver-creation layers on top would
waste the work.

## Threat model

The instinct is that a no-login URL to medication information is alarming. That
framing does not survive contact with the deployment.

**The information is already ambient.** The product is a tablet on a kitchen
table continuously displaying "Take your morning medication — two white tablets
with breakfast." Family, visiting carers and neighbours can already read it. A
secret URL on that device adds little to what the room exposes.

The real risk is the **URL escaping the device**.

**Leak vector 1 — the referrer header (most important).** `voice_reminders`
loads `https://cdn.tailwindcss.com`, so every page load ships the full URL to a
CDN. Put a token in the path and every senior's permanent credential lands in a
third party's logs. Two fixes, the second better: `Referrer-Policy: no-referrer`,
or **give the voice page its own light layout with inlined CSS**, dropping the
CDN. The second solves three problems at once — no referrer leak, no third-party
request, and a much lighter page for an old tablet. The marketing layout is the
model.

**Leak vector 2 — logs.** The token must not reach application logs, request
logs or error reports. Add it to `config.filter_parameters`; the exchange flow
already removes it from the URL after first use.

**Leak vector 3 — crawlers.** `robots.txt` disallow on `/r/` and `/start`, plus
`noindex`. A link in a search index is a link everywhere.

**Leak vector 4 — the link being shared.** Unavoidable, and the reason revocation
is first-class rather than an afterthought.

**What a leaked link actually costs:** read access to one senior's reminder
titles and times — much of it already visible in their kitchen — **plus the
ability to mark a dose as done**. That second one deserves attention: a false
"done" tells a caregiver the medication was taken when it was not, and that
signal is the entire reason the product exists. Not catastrophic, but the
strongest argument for easy revocation and visible "last used" information.

## Mechanics

### `ReminderLink`

- `user` — the senior
- `token` — `SecureRandom.urlsafe_base64(32)`, unique index, matching the
  existing `CaregiverLink.generate_pairing_token` precedent
- `revoked_at` — nullable; revoked links 404 like any unknown token
- `last_used_at` — so a caregiver can see whether a link is live or stale
- `label` — optional, e.g. "kitchen tablet", if per-device links are chosen

### Flow

1. `GET /r/<token>` looks up a live link, sets a long-lived signed cookie
   identifying the senior in **link mode**, touches `last_used_at`, and redirects
   to `/voice_reminders`
2. The token is out of the address bar and out of history going forward, and no
   longer appears in referrers
3. The bookmark still points at `/r/<token>`, so clearing cookies or resetting
   the device recovers by itself

That last point is the real advantage over simply extending the session to a
year: **a bookmarked capability URL survives cookie loss; a long session does
not.**

### Rate limiting

Guessing a 256-bit token is not a real threat, but rate-limit `/r/:token` anyway
so enumeration attempts do not fill the logs. `/start` needs it for real.

## Caregiver experience

The setup flow is where this succeeds or fails.

- Generate a link from the senior's page on the caregiver dashboard
- Show the **six-digit code** and a **QR code**
- Show `last_used_at` in plain words — "last heard from 2 hours ago", or "never
  used", which is how a caregiver notices setup silently failed
- Revoke and regenerate, with a plain warning that the old bookmark stops working
- Print-friendly, since some of this is done in person

## Privacy policy

Two disclosures, each in the same PR as the phase that introduces it:

- **Phase 1** — a new access mechanism to health-related data: that a link
  exists, what it grants, that it does not expire, and how to revoke it
- **Phase 3** — that an account can be created for someone who never signed up,
  what is stored about them, and that they can refuse

The policy has twice lagged the code in this project. It should not be a third
time. Bump the "last updated" date, which the policy itself promises.

## Phasing

**Phase 1 — links, the code exchange, read-only.** Hear and see reminders; no
acknowledgement. Includes `/start`, because a capability URL nobody can get onto
a device is not finished. Proves the setup flow, the QR code, the layout change
and the default-deny boundary, with the smallest surface. A leaked link at this
stage exposes only what the kitchen already shows.

**This phase is worth shipping alone** — it fixes a live problem for existing
seniors, and watching a real senior use it will change the design of everything
after.

**Phase 2 — done and snooze.** The third auth scheme in
`AcknowledgementsController`. Makes revocation matter.

**Phase 3 — caregiver-creates-senior.** The `provisional` state, the first-run
screen, self-revocation, and the code display on the caregiver's side.
**Requires phase 2**, for the reason given above.

**Not planned — email hand-over.** The six-digit code read over the phone already
covers remote setup, without mailing an address nobody verified. Revisit only if
something turns up that a phone call genuinely cannot do.

## What the specs must assert

The whole feature is a security boundary, so the tests are the deliverable as
much as the code:

- A link **cannot** reach the dashboard, profile, pairing, caregiver removal,
  tasks, coverage or notifications — enumerated explicitly, so a route added
  later that forgets the boundary fails here
- A link can only see and acknowledge **its own senior's** occurrences
- A revoked link 404s, and so does an unknown one — indistinguishably
- A wrong `/start` code and an expired one are indistinguishable
- A `provisional` link can author reminders and **cannot** reach any activity,
  acknowledgement or coverage route
- The signed-in experience is unchanged: existing specs pass untouched
- The voice page loads **no third-party assets**, mirroring the existing
  marketing-page assertion, since that is what stops the token leaking
- The token never appears in a rendered page after the redirect

## Open questions

1. **Who can revoke?** A senior can already remove a caregiver's access. Should
   they be able to kill their own link, or only caregivers? Leaning: both.
2. **One link per senior, or one per device?** Per-device costs a little setup
   and buys precise revocation — "the old tablet we gave away". Leaning: start
   with one per senior, add labels later.
3. **Any expiry on the link?** Leaning strongly no. Expiry reintroduces the exact
   failure this removes. `last_used_at` gives visibility without a deadline. (The
   *code* expires; the link does not.)
4. **Should the senior see they are in link mode?** Something quiet, so a
   caregiver can tell at a glance which mode a device is in.
5. **What does the caregiver see between creating the account and the senior
   starting?** "Waiting for the tablet" is honest, but a caregiver who sets up
   and goes home needs to know whether it worked. `last_used_at` may be enough.
6. **What happens when the tablet is replaced?** Regenerating is a caregiver
   action, and must not be usable to re-establish access a senior revoked.
7. **`permission` defaults to `:view`** in `generate_pairing_token`, yet the
   caregiver has to create reminders. Whether the creator gets `:manage`
   automatically — and whether the senior can see and change it — needs deciding
   rather than inheriting.
8. **Should the first-run screen offer to add an email address?** It is the
   senior's route to a real account later, but it is also more to put in front of
   someone who just wants the tablet to start talking.

## What would make this unnecessary

If asking two or three people who saw that Facebook post reveals they never got
as far as signup — that the homepage, the price or the trust was the obstacle —
then phase 3 is a large piece of work aimed at the wrong thing. **That
conversation costs an afternoon and this costs weeks.** Have it first.

Phases 1 and 2 stand regardless: they fix a problem existing seniors have every
month, whatever the reason new ones are not arriving.
