# Design: consent to be telephoned

Status: **proposed, not built.** Implements phase 1 of
`PHONE_CALL_REMINDERS_DESIGN.md`, which built the delivery machinery in PR #75
and deliberately stopped short of deciding who may be called. Tracked as #77.

The machinery works and is deployed, inert. `ENABLE_PHONE_CALL_REMINDERS` is off
and nothing in the application can set `users.phone` or
`users.voice_reminders_enabled` — both were set from a console during testing.
This document is about the missing half: how a number comes to be one Remindly
is allowed to ring.

## The thing that must not be built

A form where a caregiver types their mother's number and ticks a box.

That is the obvious implementation and it is wrong, for the reason the parent
document states plainly: **a caregiver typing a number into a form is not the
consent of the person who answers it.** Setting a monitoring tool on someone
without their knowledge is a recognised pattern in elder abuse, and a telephone
reaches further into someone's day than a dashboard does.

This codebase already solves the same problem once, structurally: the senior
generates the pairing token, so a caregiver cannot link themselves to a senior
who has not acted. Consent to be called needs the same property — not a policy
that says caregivers should ask first, but a design in which they cannot proceed
until the senior has pressed a key.

So `voice_reminders_enabled` stops being a setting and becomes a **consequence**.
Nothing writes it but a completed verification call.

## State

Five columns on `users`, four of them new:

    phone                    string     already exists, E.164 validated
    phone_verified_at        datetime   a call to this number was answered and agreed to
    call_consent_at          datetime   when the keypress happened
    call_opted_out_at        datetime   when they said stop
    voice_reminders_enabled  boolean    already exists; derived, never set directly

`phone_verified_at` and `call_consent_at` look redundant and are not. The first
says the number reaches a person who agreed; the second is the dated record of
their agreement, which is the thing that may have to be produced later. Keeping
them apart also allows a future re-verification of the same consent, or a
consent recorded by some other means, without either fact overwriting the other.

**These live on `users`, not in the audit trail.** `PruneAnalyticsJob` deletes
`Ahoy::Event` at ninety days. Consent has to outlive that by years, so it cannot
be an event.

### Consent belongs to a number, not to a person

The single most important consequence, and the one easiest to get wrong:
changing `users.phone` must clear `phone_verified_at`, `call_consent_at` and
`voice_reminders_enabled`.

Otherwise a caregiver edits the number and inherits consent for a number whose
owner never agreed to anything — which is precisely the failure the whole design
exists to prevent, arrived at through a text field. This belongs in the model as
a callback on `phone` changing, not in whatever controller happens to write it.

## The verification call

Reuses everything PR #75 built, with one structural problem to solve first.

### `telnyx_calls` cannot currently represent it

    occurrence_id  integer  NOT NULL, association required

A verification call is about a number, not a dose. It has no occurrence and
never will. Two options:

**Add a `purpose` column and make `occurrence_id` nullable.** One table holds
every call, so the per-senior daily cap, the slot allocation, the cost record
and the in-flight guard all keep working unchanged, and a verification call
correctly consumes a slot — it is a real ring on a real phone. The
`(occurrence_id, attempt_number)` unique index stops constraining verification
calls, because SQLite treats NULLs as distinct, so those need their own guard.

**Or a separate `verification_calls` table.** Cleaner types, but every guard
built in #75 would need a second implementation, and the daily cap would stop
being a cap — a senior could take ten reminder calls and ten verification calls
in a day.

Take the first. The cap is the invariant that matters and duplicating it is how
it stops holding.

`TelnyxWebhooksController` then has to branch on purpose: `handle_answered`
currently reads `call.occurrence.reminder`, which would raise for a verification
call. That branch is the point at which the two flows genuinely differ — one
announces a reminder, the other asks for agreement.

### The flow

1. A caregiver proposes a number. Nothing is scheduled and nothing rings yet.
2. **The caregiver is told to save the number in the senior's phone first.** The
   number is unknown exactly once; saved as a contact it shows a name and clears
   iOS *Silence Unknown Callers*, which otherwise sends the call to voicemail
   without ringing. This is a real setup step and often a remote one, and the
   parent document records it as the thing actually worth measuring.
3. Remindly places one verification call. It says who arranged this, what will
   happen, and asks for a keypress to agree.
4. The keypress writes `phone_verified_at`, `call_consent_at`, and sets
   `voice_reminders_enabled`. Nothing else does.
5. A "call me now" button places a single test reminder call on demand, so the
   caregiver can hear what the senior will hear before depending on it.

**No scheduled calls in phase 1.** The scheduler stays off. This proves the
consent path end to end without anything running unattended.

### A machine must never consent

If voicemail answers the verification call, no keypress can have come from a
person — but the current code cannot tell, and records a machine answering as an
answered call that collected no digit. Until #76 lands, a verification call that
is answered and yields no digit must be treated as **not consented**, never as
pending-and-probably-fine. Whichever of #76 and #77 lands second should assert
this.

## Opting out

    "Press 9 to stop these calls."

On every call, including the verification call itself. Honoured immediately and
permanently: `call_opted_out_at` is set, `voice_reminders_enabled` cleared, and
no further call is placed for any reason.

This matters more than it looks. The senior may have no other interface — the
access design notes a caregiver-created senior may have no email and can never
sign in — so the keypad is their only way to say stop. Requiring them to ask the
caregiver who arranged the calls inverts the power relationship the feature is
supposed to respect.

**Re-consent after an opt-out is an open question.** If a caregiver can simply
request verification again, "permanent" means "until they ask again", and a
senior could be re-enrolled repeatedly by the person they were trying to stop.
A cooling-off period, or requiring the senior to initiate, would fix it; both
need a decision rather than a default.

## Guards at dial time

`VoiceReminderJob` already checks the feature flag, the per-user opt-in, the
occurrence status and the calling hours, in that order, and re-reads each rather
than trusting the scheduler's query. Consent joins that list:

    return unless senior.call_consent_at.present?
    return if senior.call_opted_out_at.present?

Checked at the dial, not only at the gate, for the same reason as the others:
this job is reachable from a console and from a retry hours later, and consent
can be withdrawn in between.

## What must be impossible

1. **A call to a number that has not pressed a key to agree.** Including the
   number a caregiver just edited.
2. **A caregiver enabling calls on a senior's behalf.** No path may write
   `voice_reminders_enabled` except a completed verification call.
3. **An opt-out that does not take effect immediately**, including for a call
   already scheduled or a job already queued.
4. **Consent inferred from silence**, a voicemail, or an unanswered call.
5. **Consent surviving a change of number.**

## The UI

The caregiver dashboard shows **state**, not a checkbox:

    no number            → propose one
    proposed             → save it in their phone, then verify
    verifying            → a call is on its way
    consented (date)     → calls may be scheduled; a "call me now" button
    opted out (date)     → and what, if anything, can be done about it

The E.164 validation already on `User` should surface as a field error rather
than a 422.

The senior needs no screen for any of this, which is the point.

## Open questions

1. **What does the verification call actually say?** It is the first call a
   senior receives, before they have agreed to anything, and it has to sound
   like a service and not like a scam in about five seconds. Amber Nightingale
   at AARP was asked this directly on 2026-08-23 and has not yet replied; her
   answer should shape the script rather than be checked against it afterwards.
2. **Re-consent after opt-out** — see above.
3. **Does the caregiver hear the verification call's outcome?** Telling them "she
   declined" is information about the senior that the senior did not choose to
   share. Telling them nothing leaves them unable to act.
4. **Does a verification call consume the daily cap?** It rings a real phone, so
   probably yes — but a senior who declines three times would then be
   uncallable for the rest of the day, which may be the correct outcome.
5. **The column is named `voice_reminders_enabled`; the parent document calls it
   `call_reminders_enabled`.** Worth reconciling before more code depends on it.

## What would make this unnecessary

If the answer to gate 2 comes back badly — if families say their parents will
not pick up, or that the beeping pill box already works — then none of this gets
built, and the honest conclusion is that the telephone was the wrong channel.
That question is out with three caregivers now.
