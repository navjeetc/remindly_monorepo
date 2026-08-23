# Design: reminders that telephone the senior

Status: **partly built, not fit to enable.** The call itself works end to end and
has been verified against a real handset: dial, speak the reminder, collect one
DTMF digit, acknowledge or snooze, notify the caregiver. Calling hours are
enforced in the called party's own timezone, and an unresolvable timezone blocks
the call rather than defaulting to anything.

What is **not** built is the part this document argues matters most: there is no
consent record, no number verification, and no answering-machine detection. The
gates in "Before any code" remain decisions only Navjeet can make, and production
has no Telnyx credentials, so nothing is enabled there.

Proposed 2026-08-18; first working call 2026-08-23. Read alongside `SENIOR_ACCESS_DESIGN.md`, which solves an
overlapping problem by a different route — see "Relationship to the access
design" below, because the two together decide how much of each is worth
building.

## The problem

Remindly speaks through a browser page, so that page has to stay open on a
device the senior owns, powered, awake, signed in, and not accidentally closed.
Every public page of the site says so plainly, because it is true and hiding it
would be worse. It is also the single most common reason a family decides this
will not work for them, and `SENIOR_ACCESS_DESIGN.md` exists because the session
behind that page expires roughly monthly and takes the reminders with it.

A telephone call asks none of that. No device to buy, no tab, no session, no
tap-to-unlock-audio, no charging, no browser, no password, nothing to close by
accident. It reaches a landline and a fifteen-year-old flip phone. For a
meaningful share of "an older parent living independently", it is the only
channel that reaches them at all.

The keypad interface is also the one this audience already knows. `Acknowledgement`
is already `enum :kind, { taken: 0, snooze: 1, skip: 2 }` — press 1, 2, 3 is not
a new vocabulary, it is the existing one spoken aloud.

## What it does not solve

- **The caregiver still needs a screen.** Setting up reminders, seeing the day,
  linking family — none of that moves to the phone.
- **It is lossy.** No list of what is next, no notes, no reading back a week.
- **It does not know anything new.** A call proves the phone was answered and a
  key was pressed. It cannot prove a tablet was swallowed, and it introduces a
  second gap of its own — see "The honesty problem".

## The blocker: this is the first feature with a marginal cost

Every existing feature costs nothing per user. One SQLite file on one
DigitalOcean box serves everybody, and the only per-message cost in the product
is transactional email, which is negligible and bounded by how often a caregiver
does something.

Calls are not like that. Working figures, to be re-checked against current
provider pricing at build time rather than trusted from here:

| Item | Rough cost |
| --- | --- |
| US outbound voice | ~$0.014/minute, billed per minute begun |
| A reminder call answered by a person | ~30–45s, so one billed minute |
| Answering-machine detection | priced separately, per call |
| A dedicated phone number | ~$1.15/month |

A senior with four medication reminders a day is about 120 calls a month.
Allowing for retries on no-answer, **$3–5 per senior per month**, every month,
whether or not that family ever becomes worth anything.

The site currently says: free, no card, no ads, no sales calls, no trial that
quietly ends, no limit on how many reminders you set. That sentence is on the
homepage, the FAQ and the landing page, and it is meant. **"We telephone your
mother four times a day, unlimited, free" cannot be meant**, so this feature
forces the monetisation decision that has been deferred since July.

Options, none of them chosen:

1. **Charge for calls only.** Everything currently free stays free; the phone
   channel is the paid tier. Honest, and it prices the thing that actually costs.
2. **A call allowance.** N calls a month included, more if you pay. Keeps "free"
   true for a light user; adds metering, a counter the family can see, and a
   decision about what happens when the allowance runs out mid-week — which for
   medication is an unpleasant thing to design.
3. **Absorb it.** Viable only at a handful of families, and it sets an
   expectation that gets withdrawn later, which is exactly the pattern the FAQ
   promises Remindly will not follow.

Nothing below should be built before this is settled, because the answer changes
the schema (allowances, billing) and the copy.

## Before any code

Three gates, in order. Two are not engineering.

1. **Decide the monetisation model.** Above.
2. **Ask three or four families whether the caregiver could get one number saved
   on their parent's phone.** The original form of this question was "does your
   parent answer unknown numbers", and the answer is no — this demographic is
   trained, correctly, not to. But the `from` number is static, so it is only
   unknown once. Saved as a contact it displays a name, and it also clears iOS
   **Silence Unknown Callers**, which otherwise routes the call to voicemail with
   no ring at all.

   That moves the risk somewhere more interesting. It is no longer "will she
   answer a stranger" but "will a caregiver four hundred miles away get one
   contact saved on someone else's phone" — which is precisely the class of task
   this product exists because it is hard. Measure that, not the stranger
   question. Ask also what happens today: many already have a pill box that
   beeps, and it may be enough.

   Two cases the contact does not cover, and both are setup work rather than
   blockers. **A landline cannot hold a contact** — there the only signal is
   CNAM, which is reliable on landlines and patchy on mobile, the reverse of the
   contact story, so CNAM registration is a real task. And **carrier spam
   labelling sits upstream of the contact list**: a number with a poor reputation
   can be flagged or blocked before the handset ever consults its contacts, which
   is the argument below for a dedicated number.

   If saving the contact is load-bearing, it is a setup step and not FAQ advice —
   arguably a gate, with nothing scheduled until the caregiver confirms it is
   done. That also fixes an ordering problem, because the consent call is itself
   the first call and is the one that most needs to land. The sequence is: save
   the contact, then the consent call, then anything scheduled.
3. **Establish what the phone number actually is.** Navjeet has a number in a
   GoHighLevel subaccount, A2P-verified. Two things follow, both settled before
   anyone writes code:
   - **A2P 10DLC is a messaging registration and does not apply to voice.** It
     governs application-to-person SMS on 10-digit long codes. Automated outbound
     voice is governed by TCPA, STIR/SHAKEN attestation and caller-ID
     reputation. The verification already paid for buys nothing on this path. It
     would matter for SMS reminders, which are a different feature.
   - **A GHL-provisioned number is not usable from Rails.** If the number lives
     in GoHighLevel's own phone system there are no raw provider credentials for
     it, and their workflow actions are not built to hand a DTMF digit back to
     this application against a specific occurrence. If instead it is a number in
     Navjeet's own Twilio account that GHL is connected to, it is technically
     usable. Check under Settings → Phone Numbers.

**Use a dedicated number regardless.** This is the same argument already made and
accepted for keeping bulk marketing off Postmark, because Postmark's reputation
carries the magic sign-in links. If a CRM number ever sends marketing, collects
complaints, or picks up a "Spam Likely" label, medication reminder calls stop
landing — silently, discovered only after something has been missed. A number is
$1.15 a month and is the cheapest insurance in the feature. A shared number also
prevents the senior from learning one number as "that is my reminder", and a
provider number has exactly one voice webhook, so pointing it at Rails takes it
away from GHL permanently.

## The central safety property: consent belongs to the person who answers

`SENIOR_ACCESS_DESIGN.md` states it for the tablet and it is more acute here:
setting a monitoring tool on someone without their knowledge is a recognised
pattern in elder abuse, and the current pairing flow prevents it structurally
because the senior generates the code.

A caregiver typing their mother's phone number into a form is **not** her
consent, and here that is not only an ethical matter. Automated and prerecorded
voice calls are regulated, consent runs to the called party, and calls are
restricted to 8am–9pm in the called party's local time. Whether a given design
satisfies TCPA and its state equivalents is a legal question and is not one to
guess at — the same boundary already drawn for the privacy policy and terms.
What follows is the shape the code must support, not an opinion that it is
sufficient.

The hours half of this is built: `User#within_calling_hours?` is checked both by
the scheduler, so out-of-window occurrences enqueue nothing, and by
`VoiceReminderJob` itself, because that job is reachable from a console or a
retry hours after the failure that caused it. It cannot help with a timezone that
is wrong but valid — the UTC-12 bug resolved perfectly well — which is why the
consent call below matters: it is the one moment a real person confirms the
number reaches them.

**Consent is captured on the phone, by the person holding it.** The number is
verified by placing one call that says who set this up and what will happen, and
asks for a keypress to agree. Nothing is scheduled until that keypress exists.
Every reminder call ends with the way out, and honouring it is immediate and
permanent until re-consented.

**Consent has to outlive the analytics window.** The audit trail at
Admin → Audit Logs reads Ahoy events, and `PruneAnalyticsJob` deletes those at 90
days. Consent therefore cannot live there — it is a durable column or a record of
its own, and the pruning job must never be able to reach it.

## What this is not allowed to become

**A robocall.** The failure mode is not annoyance, it is fraud-shaped. An
automated voice telling an older person to do something and press a key is the
exact shape of the scam calls this demographic is warned about weekly, and
Remindly must not train anybody to comply with that pattern. Concretely: the call
opens with the senior's own name and the word Remindly before any instruction,
says who set it up, never asks for any information, never asks for a callback,
and never asks for a digit that means anything other than "done", "later" or
"stop".

**A surveillance channel.** It reports whether a key was pressed. It does not
report where anyone is, does not record audio, and does not tell a caregiver that
a call went unanswered in any language stronger than the missed-reminder email
already uses.

**A silent failure.** Carrier spam labelling, a wrong timezone or a lapsed number
all break this in ways nobody notices. Delivery outcomes are recorded per attempt
and visible, and a family can place a test call themselves at any time.

## Invariants

Things that must be impossible, not merely discouraged.

1. **No call is ever placed to a number that has not consented by keypress**, and
   opt-out is honoured immediately and permanently.
2. **A call is only ever placed inside the legal window in the called party's own
   timezone.** `users.tz` is what decides this, which makes it load-bearing in a
   way it has never been: the profile bug fixed on 2026-08-16 silently moved
   savers to UTC-12, and under this feature that same bug would have telephoned
   people in the middle of the night. A tz that fails to resolve blocks the call
   rather than defaulting.
3. **The digit chooses the action; the call identifies the reminder.** The
   occurrence is looked up from the provider's call identifier, never from
   anything in the request body. A keypress can never acknowledge a reminder
   other than the one its call was placed for.
4. **Webhooks are rejected unless the provider signature verifies.** This is a
   public, unauthenticated endpoint that writes acknowledgements.
5. **Placing a call is idempotent per occurrence and attempt.** A retried job
   never dials twice.
6. **No call is placed for an occurrence already acknowledged.** Status is
   re-checked at dial time, as `ReminderNotificationJob` already re-checks before
   notifying.
7. **A per-senior daily cap exists and cannot be configured away** by a caregiver.
8. **The senior can stop the calls without signing in, without a caregiver, and
   without a screen** — the keypress out is always available.

## The honesty problem

The whole site is built on one careful distinction: Remindly records that
somebody pressed Done. It does not know a tablet was swallowed. That language is
enforced by specs on the homepage and the landing page.

Calls add a second gap. **A call answered is not a call heard**: answering
machines and voicemail pick up constantly, someone may set the handset down, and
a person who answers may not take in a word of it. So the chain becomes: call
placed → call answered → answered by a human → key pressed → dose taken, and only
the first four are observable, with the third only probabilistically.

Consequences, all of which are copy decisions to be made before shipping, not
after:

- **Voicemail is not delivery.** If a machine answers, the attempt is recorded as
  such and the occurrence is not treated as reached.
- The missed-reminder email already carries the caveat that an unmarked reminder
  is not evidence of a skipped dose. It needs a second sentence for the case where
  nobody answered the phone, which is weaker evidence still.
- The FAQ and the landing page need this stated in the same voice as the existing
  limitation, not buried in a footnote.

## Mechanics

### Schema

On `users` — the senior's own record:

    phone                    string    # E.164, nil until given
    phone_verified_at        datetime
    call_consent_at          datetime  # the keypress; nil means never call
    call_opted_out_at        datetime  # set by keypress or by anyone; wins over consent
    call_reminders_enabled   boolean   default false

A new `call_attempts` table — delivery outcomes stored separately from the
reminder definition, which is what the competitor-gap plan asks for and what
`occurrences` already does for schedules:

    occurrence_id            integer   not null, indexed
    user_id                  integer   not null   # who was called
    provider                 integer   # enum
    provider_call_sid        string    not null, UNIQUE   # idempotency lives here
    attempt_number           integer   not null
    status                   integer   # queued/ringing/answered/no_answer/busy/failed/completed
    answered_by              integer   # human/machine/unknown
    digit                    string    # what was pressed, nil if nothing
    started_at, ended_at     datetime
    duration_seconds         integer
    cost_cents               integer
    UNIQUE (occurrence_id, attempt_number)

Nothing changes on `occurrences` or `acknowledgements`. The statuses
(`pending / acknowledged / missed`) and kinds (`taken / snooze / skip`) already
cover this channel exactly.

### The flow

1. `MakeReminderCallJob` is enqueued for an occurrence, gated on: feature enabled
   for this user, consent present and not withdrawn, inside the legal window in
   `users.tz`, under the daily cap, occurrence still `pending`.
2. It places one call and writes a `CallAttempt` with the provider's call id
   before anything can come back.
3. The provider fetches instructions and speaks: name, "this is Remindly",
   who set it up, then the reminder, then "press 1 if you have done it, 2 to be
   reminded again in ten minutes, 9 to stop these calls."
4. A keypress posts to a webhook. Signature verified, `CallAttempt` found by call
   id, occurrence taken **from that record**, then the existing acknowledgement
   write happens unchanged: an `Acknowledgement` row and a compare-and-swap on
   `Occurrence.status` inside one transaction. A duplicate webhook finds the row
   already acknowledged, writes nothing, notifies nobody twice.
5. Status callbacks update the attempt — answered, machine, busy, no answer.
6. No answer or busy retries after a few minutes, twice at most, then stops. The
   existing `MarkMissedOccurrencesJob` continues to own what "missed" means; this
   feature does not introduce a second definition.

**The acknowledgement does not go through `AcknowledgementsController`.** That
controller already juggles a session scheme and a Bearer scheme, and its header
comment records that fixing one previously broke the other. A provider webhook is
authenticated by signature, not by a user, and belongs in its own controller that
never calls `authenticate!` and never reads an occurrence id from params. Sharing
the endpoint would mean a fourth auth scheme in a place with a history of them
breaking each other.

### Provider

Twilio, on the boring-choice principle: `<Gather numDigits="1">` is precisely
this flow, the status callbacks and answering-machine detection are documented,
and if the GHL number turns out to be a bring-your-own-Twilio number the
credentials already exist. Telnyx is cheaper at volume, which is not a
consideration at this size. The provider is behind one class either way, because
the second provider is always cheaper than the first and this should not be a
rewrite.

Caller-ID display name is worth setting and worth not relying on: coverage on
mobile is patchy. **What the call says in its first five seconds is the real
defence against being taken for a scam**, not the name on the screen.

### Feature flag

`FeatureFlag` already exists with an env-var-backed pattern
(`ENABLE_NATIVE_SCHEDULING`). Add `phone_call_reminders`, default false, and gate
per user as well — the flag says the code may run, the user's own
`call_reminders_enabled` says whether it runs for them.

## Relationship to the access design

`SENIOR_ACCESS_DESIGN.md` proposes signing-in-free links so a senior stops being
silently logged out, and lets a caregiver create a senior who has no email
address at all. That document notes such a senior can never sign in, so link mode
is their only mode.

**Phone calls are a second answer to the same question, and the two compose
unusually well.** A caregiver-created senior with no email and no tablet is
completely unreachable today; with a phone number and consent they are reachable
without a screen existing anywhere in their house. That is the strongest version
of the product's promise, and neither document reaches it alone.

They do not make each other unnecessary:

- Links cost nothing per use; calls cost money every time. A family that will use
  a tablet should use the tablet.
- Calls are lossy — no list, no history, no notes. The tablet stays the better
  interface for anyone who will actually look at one.
- A senior who wants both should get both, with the call as the thing that
  catches what the screen missed.

Sequencing them is a real decision and is deliberately left open below.

## Phasing

**Phase 0 — no code.** The three gates above.

**Phase 1 — consent and a test call.** A caregiver enters a number; Remindly
places one verification call; the senior presses a key to agree. A "call me now"
button places a test reminder call on demand. **No scheduled calls at all.** This
proves dialling, answer detection, DTMF capture, signature verification, consent
capture and cost recording end to end, and it is independently useful: it is the
"prove it works before you depend on it" step the competitor-gap plan asks for.

**Phase 2 — scheduled calls, medication only.** Retries, daily cap, quiet hours,
opt-out, per-user flag. Medication only for the same reason caregiver
notifications shipped medication-only: it is the category where the value is
worth the intrusion, and hydration reminders several times a day would be
intolerable by telephone and expensive.

**Phase 3 — only if phase 2 earns it.** Other categories, escalation to a
caregiver when a call goes unanswered, and an inbound number the senior can ring
to hear what is next. Inbound is cheap and might well be more popular than
outbound; it is deliberately not in phase 1 because it proves nothing about
delivery.

## What the specs must assert

- No call without consent; opt-out blocks immediately and permanently.
- No call outside the legal window in the user's own timezone, and none at all
  when the timezone is missing or unresolvable.
- No call for an occurrence already acknowledged; no second call for the same
  occurrence and attempt when the job is retried.
- A webhook with a bad signature is rejected and writes nothing.
- A keypress cannot acknowledge an occurrence other than the one belonging to its
  call — asserted by attempting it, not by inspection.
- A duplicate webhook writes one acknowledgement and notifies caregivers once.
- A machine-answered call does not acknowledge and does not count as reached.
- The daily cap holds, and a caregiver cannot raise it.
- Cost is recorded per attempt, so the bill can be explained.

## Open questions

1. **Who pays, and how?** The gate above. Everything else depends on it.
2. **Whose phone?** The senior's, obviously — but a caregiver may want the
   fallback call when their parent does not answer. That is phase 3 and it is
   also the point where this stops feeling like a reminder and starts feeling like
   an alarm system, which the terms say Remindly is not.
3. **Does voicemail get a message left?** Leaning yes for the reminder itself, and
   never for anything that sounds like a status report about a person.
4. **How many retries, and how far apart?** Each one costs money and patience.
   Leaning: two, ten minutes apart, then stop and let the existing missed sweep
   do its job.
5. **Is the senior's phone number visible to caregivers?** They typed it, so
   probably — but a senior who later changes it should not have to explain that to
   anyone.
6. **Does `skip` (3) exist on the call?** It exists in the enum. Three options is
   already a lot to hold on a phone call, and "later" and "done" cover most of it.
7. **Landline or mobile?** Worth detecting, because a landline cannot be carried
   to the kitchen and a mobile may be on silent.
8. **Who writes the script, and does it ever change?** A call is the most
   intimate thing this product does. The wording deserves the same care the
   missed-reminder email got, and probably a real person reading it aloud rather
   than a synthesised voice — which costs nothing extra for a fixed preamble and
   cannot be done for the reminder text itself.
9. **Sequencing against `SENIOR_ACCESS_DESIGN.md`.** Both address the same
   failure. Links are cheaper to run and harder to build; calls are the reverse.

## What would make this unnecessary

If the families interviewed say their parent will not answer an unknown number,
or that the pill box that beeps is already enough, this is weeks of work aimed at
a problem they do not have.

If instead the answer is that they would answer a call from a number they had
been told about, then this is the most valuable thing in the backlog, because it
is the only item that removes the constraint every other part of the product has
had to design around.

**That conversation costs an afternoon. This costs weeks. Have it first.**
