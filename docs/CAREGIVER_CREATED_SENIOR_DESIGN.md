# Design: the caregiver sets it up — removing the two-inbox handshake

Status: **proposed**, not built. Written 2026-08-09.

Depends on `docs/REMINDER_LINKS_DESIGN.md`, which is **not on `main`** — it lives
on the unmerged branch `docs/reminder-links` (commit `a4fa464`, written
2026-07-27) and is itself proposed rather than built. Deliberately not linked
relatively, because that link would 404 for anyone reading this from `main`.

This document does not restate it and should not be implemented without it. If
that branch is abandoned, this proposal needs rewriting rather than adapting: the
token model is load-bearing here.

## The problem

The homepage promises "You create the reminders." It cannot currently be done.

The real path from "I'll try this" to a parent hearing a reminder is:

1. The caregiver signs in — magic link, email round trip
2. **The senior signs in on their own device, with their own email address**,
   navigates to `dashboard/generate`, and produces a pairing code
   (`dashboard_controller.rb:151`)
3. The caregiver enters that code at `dashboard/pair`
4. The caregiver creates a reminder — only now possible, since
   `dashboard#senior` requires an existing `caregiver_link`
5. The senior's device gets the page opened, left open, and tapped once to
   unlock audio

There is no route for a caregiver to create a senior. `invite_caregiver` runs
senior → caregiver; the reverse does not exist.

So setup needs two people, two inboxes and two devices — and the harder half
falls on the person who, by the product's own description, is the one having
trouble with this sort of thing.

### The evidence that this matters

A Facebook post on 2026-08-08 brought **17 people** to the site. Three clicked
past the homepage. **Nobody signed up.** The five homepage fixes from early-user
feedback had already shipped, so the obvious copy explanations were already
addressed.

That is not proof this is the cause — nobody has been asked yet, and that
conversation is still the most valuable thing available. But it is the largest
known obstacle sitting directly behind the signup button, and it is one we can
describe precisely rather than guess at.

## What this proposes

The caregiver creates the account for the person they care for, sets up the
reminders, and hands over a link. The senior's entire involvement becomes:
**open this link and leave the page up.**

The intended scene is an adult child sitting in their parent's kitchen with a
tablet, which is also why the hand-over is a link or QR code rather than an
email — see "Do not email the senior" below.

## What this is not allowed to become

The pairing step being removed is not merely friction. `generate_pairing_token`
is created **by the senior**, on their own account, and `pair_with` grants access
to whoever presents the token. Consent is a structural property today: access
cannot exist unless the person receiving reminders acted.

A monitoring tool set up on someone without their knowledge is a recognised
pattern in elder abuse. The current design prevents it by accident. Any
replacement has to prevent it on purpose.

**The resolution: consent moves from "before setup" to "at first use". It does
not disappear.** Nothing is spoken, nothing is recorded, and the caregiver sees
no activity until the senior's device opens the link. That moment is when they
are told who set this up and can refuse.

## Invariants

These are the things that must be impossible, not merely discouraged.

1. **A caregiver-created account is always a new account**, never an attachment
   to an existing one. Auto-linking would hand over an existing person's
   history — their reminders, their acknowledgements, their other caregivers —
   to whoever typed their address.
2. **This flow never asks for the senior's email address.** See "Do not ask for
   the senior's address" below. This is what makes invariant 1 structural: with
   no address there is no lookup, so there is nothing to collide with and no way
   to ask the form whether somebody already uses Remindly.
3. **Nothing happens until the senior's device opens the link.** No mail, no
   speech, no acknowledgements, and nothing for the caregiver to look at.
4. **The senior can always refuse.** The first screen names who set this up and
   offers to stop it, in one action, without signing in.
5. **The senior is told when any caregiver is added**, not only the first.
6. **A caregiver cannot create accounts in bulk.** Rate limited per caregiver.

## Do not email the senior

The obvious hand-over is to email the parent a link. It should not be v1, for a
reason that has already cost this project once.

Emailing an address the app has never verified means any signed-in user can send
mail from `hello@remindly.care` to an arbitrary address. Bounces and complaints
follow. Every message in this app — including magic links — leaves that same
domain, so the end state of poor sender hygiene is that **nobody can log in**.
That is not hypothetical: see the changelog entry **"Stop mailing addresses that
no longer exist"** under `Unreleased` → `Fixed`, where mailing two non-existent
addresses for sixteen days was worth a PR of its own.

A link or QR code handed over in person avoids all of it, and matches the
scenario the product is actually for. Remote setup can come later, with rate
limits per sender and per target address, once there is a reason to want it.

## Do not ask for the senior's address

The first draft of this document collected the senior's email "optionally" and
said that an address already in use would quietly fall back to pairing. Review
found that this cannot work, and the objection is correct: if the address exists,
no account can be created, so the caregiver cannot go on to write reminders — and
a flow that visibly stops in one case and continues in the other **is** the
enumeration oracle invariant 2 was written to prevent. Identical responses and
"carry on with setup" are not simultaneously satisfiable.

Rather than paper over it, drop the field. **A senior created this way has no
email address at all.**

This is coherent with the rest of the design rather than a concession:

- We already decided not to email them (see below), so the address had no use.
- No address means no lookup, no collision, no branch, and no oracle.
- It matches the scene: someone setting up a tablet in their parent's kitchen
  should not have to know which of three addresses their mother still reads.

Two consequences to design for:

- `User` validates `email` for presence and uniqueness. Link-only seniors need
  that relaxed — and must be **structurally unmailable**, not merely unmailed.
  The `email_undeliverable_at` machinery added on 2026-08-09 is the natural
  place: no address means no delivery attempt, ever.
- Such an account cannot be recovered and cannot sign in. If the senior later
  wants a real account — to manage caregivers, or to use the app properly —
  they add their own address themselves, which is the same consent step this
  design moved to first use, arriving when it is actually needed.

## The states a link moves through

Review found a second hole, and it is the sharper of the two.
`CaregiverLink#pending?` means `caregiver_id` is `nil`, while every caregiver
action authorises through `current_user.caregiver_links`. So in the first draft:

- leave `caregiver_id` unset and the caregiver **cannot create reminders**, which
  is the entire point of the feature; or
- set it immediately and the existing activity routes — `dashboard#senior`, the
  acknowledgement history, the coverage views — become reachable **before the
  senior has consented**, which violates invariant 3.

Neither is acceptable, so the state has to be explicit rather than inferred from
whether a foreign key is null. Three states, not two:

| State | Meaning | Caregiver may |
|---|---|---|
| `pending` | senior generated a token, no caregiver yet (**today's behaviour, unchanged**) | nothing |
| `provisional` | caregiver created the account; senior has not opened the link | create and edit reminders |
| `active` | the senior opened the link and chose to start | everything they can do today |

`provisional` is the new one, and the rule that matters is that **authorisation
splits by state, not by whether data happens to exist yet**. Reminder authoring
accepts `provisional` or `active`; every activity, acknowledgement and coverage
view requires `active`. Invariant 3 then holds because the routes refuse, not
because the account happens to be empty — which is the difference between a
guarantee and a coincidence.

Refusal at the first-run screen destroys the `provisional` link and the account
with it. That is safe precisely because a provisional account contains nothing
but reminders the caregiver typed: there is no history to lose, because none can
have been created yet.

## Where this meets the reminder link design

This feature needs a no-login URL for the senior's device. `REMINDER_LINKS_DESIGN`
already specifies one — `/r/<token>`, a capability URL, with `reminder_link_user`
kept deliberately separate from `current_user` so that controllers are
unreachable by link unless they name it. **Build that first; do not invent a
second token system.**

Two things this document adds to it.

### The first-run screen

The reminder link design describes a URL that goes straight to the voice page.
For a caregiver-created account, the *first* open must instead show a short
screen: who set this up, what it will do, and two choices — start, or stop this.
Afterwards the link behaves exactly as that document describes.

### A capability may revoke itself

`REMINDER_LINKS_DESIGN`'s capability table says a reminder link explicitly
**cannot** remove a caregiver's access, and it is right: if it could, anyone
holding a leaked URL could cut a family off from a vulnerable person's care.
That is a denial-of-care attack, and it is worse than the disclosure it would
prevent.

But invariant 4 above requires a senior who never signs in to be able to refuse.
Both cannot be true as stated.

The resolution is narrow: **the link may destroy itself.** "Stop this" revokes
the token and the pending caregiver link — the thing the caregiver set up stops
existing. It does not reach into account management, does not remove established
caregivers, and cannot be used against a senior who is already set up, because a
revoked token 404s like any unknown one.

Full caregiver management continues to require a real sign-in. A capability that
can end itself is not the same as a capability that can act on the account, and
only the first is needed here.

## The flow

**Caregiver:**

1. Signs in as they do today
2. "Set up reminders for someone" — enters **a name only**. No email address is
   asked for, so there is no branch here and no lookup
3. A new senior account is created with no address, a **`provisional`**
   `CaregiverLink`, and a reminder-link token
4. Creates the first reminders — permitted because the link is `provisional`
5. Gets a **six-digit code** and a QR code, with plain instructions for the
   tablet — see "Getting the link onto the device"

**Senior, once, on their device:**

6. Goes to `remindly.care/start` and types the six digits → the first-run screen:
   *"Jane set up reminders for you on Remindly. It will say them out loud when it
   is time. Start, or stop this."*
7. Taps start → the link becomes `active`, then the audio unlock that the voice
   page already requires
8. The page stays open

Between steps 3 and 7 the caregiver can write reminders and nothing else: the
activity, acknowledgement and coverage routes all require `active` and refuse a
`provisional` link outright. If the senior chooses "stop this" at step 6, the
link and the account are destroyed, and nothing has been recorded about them —
because nothing could have been.

## Getting the link onto the device

The first draft said the caregiver "gets a link and a QR code" and left the hard
part unsaid. `REMINDER_LINKS_DESIGN` has the same gap: it describes a device
visiting `/r/<token>` and bookmarking it, but not how a 43-character token
reaches a tablet in the first place.

The obvious answers all fail:

- **Typing the URL.** The token is `SecureRandom.urlsafe_base64(32)` — 43
  mixed-case characters, on a tablet keyboard, for someone whose eyesight is
  part of why you are setting this up.
- **QR code alone.** Fine on a tablet with a camera and a scanner that behaves.
  Useless on the desktop computer in the kitchen, which is one of the devices
  the FAQ explicitly says works.
- **Email.** Ruled out above, for reasons that have not changed.

### Move a short code, not a long URL

The pattern every television app uses, for exactly this problem:

1. The caregiver's screen shows a **six-digit code** (and a QR code as a
   shortcut for devices that can scan)
2. On the senior's device, someone goes to **`remindly.care/start`** — short
   enough to type, and short enough to say
3. They type the six digits
4. The server exchanges the code for the durable capability and redirects to
   `/r/<token>`, which then does exactly what `REMINDER_LINKS_DESIGN` specifies:
   sets the signed cookie, drops the token out of the address bar, lands on the
   voice page
5. Bookmark it or add it to the home screen. The bookmark holds `/r/<token>`, so
   the "survives cookie loss" property in that document still holds

The QR code encodes the `/r/<token>` URL directly, so both routes converge.

### The part that makes this more than a convenience

**Six digits can be read down a telephone.** That makes remote setup possible
without ever emailing an unverified address: you are at home, your mother is at
hers, you talk her through typing `remindly.care/start` and read her the numbers.

It is worth noticing that this is the one channel this audience is most
comfortable with. Every other remote option asks an older person to find a
message in an inbox and trust a link inside it — the exact interaction they are
told never to trust.

### What this costs

A six-digit code is guessable in a way a 256-bit token is not, so the exchange
endpoint carries the security burden the capability URL does not:

- **Short expiry** — ten minutes is enough to walk to another room, and short
  enough that a guessed code is unlikely to still be live
- **Single use**, and bound to one `provisional` link
- **Hard rate limiting** on `/start`, per IP and per code. Rails 8's
  `rate_limit` is already used in `SubscribersController`
- **No enumeration signal** — a wrong code and an expired code must be
  indistinguishable
- Codes must be generated with `SecureRandom`, not `rand`

None of this is novel, and all of it has to be in the reminder-links work rather
than bolted on afterwards — which is a change to the phasing below.

## Open questions

1. ~~**Does the senior need an email address at all?**~~ **Answered by review:
   no, and asking for one optionally is worse than not asking.** See "Do not ask
   for the senior's address". What remains open is the consequence: a link-only
   account cannot be recovered if the link is lost, and the senior cannot sign in
   to manage caregivers until they add an address themselves. Whether the
   first-run screen should offer that immediately, or wait until it is needed, is
   a judgement about how much to put in front of someone who just wants the
   tablet to start talking.
2. **What does the caregiver see between steps 5 and 6?** "Waiting for the tablet
   to be set up" is honest, but a caregiver who does the setup then goes home
   needs to know whether it worked.
3. **What happens when the tablet is replaced?** Regenerating a link is
   presumably a caregiver action, and it must not be usable to re-establish
   access a senior revoked.
4. **`permission` defaults to `:view`** in `generate_pairing_token`, yet the
   caregiver has to create reminders. Whether the creator gets `:manage`
   automatically — and whether the senior can see and change that — needs
   deciding rather than inheriting.

## Phasing

1. `REMINDER_LINKS_DESIGN`, in full — **plus the `/start` code exchange**, which
   belongs there rather than here. A capability URL nobody can get onto a device
   is not finished, and that document has the same gap this one had.
2. Caregiver-creates-senior, first-run screen, self-revocation, and the code and
   QR display on the caregiver's side.
3. Privacy policy updated **in the same PR**, because this stores personal data
   about someone who never signed up. The policy has twice lagged the code in
   this project; it should not be a third time.
4. Remote hand-over by email — **probably never.** The six-digit code read over
   the phone already covers setting this up from a distance, without mailing an
   address nobody has verified. Revisit only if something turns up that a phone
   call genuinely cannot do.

## What would make this unnecessary

If asking two or three people who saw that Facebook post reveals they never got
as far as signup — that the homepage or the price or the trust was the obstacle —
then this is a large piece of work aimed at the wrong thing. **That conversation
costs an afternoon and this costs weeks.** Have it first.
