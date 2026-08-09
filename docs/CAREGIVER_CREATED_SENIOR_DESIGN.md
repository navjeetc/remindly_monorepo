# Design: the caregiver sets it up — removing the two-inbox handshake

Status: **proposed**, not built. Written 2026-08-09.

Depends on [`REMINDER_LINKS_DESIGN.md`](REMINDER_LINKS_DESIGN.md), which is also
proposed and not built. This document does not restate it and should not be
implemented without it.

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

1. **A caregiver-created account is always a new account.** If the address
   already exists, this path must refuse and fall back to consent-based pairing.
   Auto-linking to an existing account would hand over an existing person's
   history — their reminders, their acknowledgements, their other caregivers —
   to whoever typed their address.
2. **The response is identical whether or not the address exists.** Otherwise the
   form answers "does this person use Remindly?" to anyone who asks, which is a
   disclosure in its own right.
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
That is not hypothetical: see the `Fixed` entry for 2026-08-09 in the changelog,
where mailing two non-existent addresses for sixteen days was worth a PR of its
own.

A link or QR code handed over in person avoids all of it, and matches the
scenario the product is actually for. Remote setup can come later, with rate
limits per sender and per target address, once there is a reason to want it.

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
2. "Set up reminders for someone" — enters a name and, optionally, an address
3. A new senior account is created, with a pending `CaregiverLink` and a
   reminder-link token. If the address already exists: identical response, but
   the pairing path is used instead (invariants 1 and 2)
4. Creates the first reminders
5. Gets a link and a QR code, with plain instructions for the tablet

**Senior, once, on their device:**

6. Opens the link → the first-run screen: *"Jane set up reminders for you on
   Remindly. It will say them out loud when it is time. Start, or stop this."*
7. Taps start → the audio unlock the voice page already requires
8. The page stays open

The caregiver sees nothing until step 6, and the account is inert until then.

## Open questions

1. **Does the senior need an email address at all?** If the caregiver never
   supplies one, the account cannot be recovered, and the senior can never sign
   in properly to manage caregivers. Making it optional is friendlier and may
   trap people. Making it required reintroduces a piece of the problem this
   feature exists to remove.
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

1. `REMINDER_LINKS_DESIGN`, in full. Nothing here works without it.
2. Caregiver-creates-senior, hand-over link, first-run screen, self-revocation.
3. Privacy policy updated **in the same PR**, because this stores personal data
   about someone who never signed up. The policy has twice lagged the code in
   this project; it should not be a third time.
4. Remote hand-over by email, with rate limits, if and only if there is evidence
   people want to set this up without being in the room.

## What would make this unnecessary

If asking two or three people who saw that Facebook post reveals they never got
as far as signup — that the homepage or the price or the trust was the obstacle —
then this is a large piece of work aimed at the wrong thing. **That conversation
costs an afternoon and this costs weeks.** Have it first.
