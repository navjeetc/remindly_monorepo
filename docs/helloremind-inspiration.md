# HelloRemind as a model for Remindly

**Purpose:** work out what Remindly should take from HelloRemind
(`helloremind.me`), which sells the product Remindly gives away: automated
reminder calls for an older person, set up by the family who care for them.

## Read this first: how much of the below is actually evidence

**The site could not be opened.** `helloremind.me` and `www.helloremind.me` are
both blocked by the network egress proxy on the machine this was written on, so
every claim about HelloRemind here comes from search-index summaries of their
`/about` and `/help` pages, not from the pages themselves.

That has two consequences, and the second is the more important:

- **The functional claims below are quotable but thin.** They are HelloRemind's
  own marketing wording as a search index recorded it. Nobody has seen the
  product, a signup flow, a price, or a call.
- **The UI half of this document does not exist, and could not be faked.** Not
  one screenshot, colour, layout or piece of page structure was observed. Any
  "UI direction inspired by HelloRemind" written from here would be invention
  with a competitor's name attached to it, which is worse than nothing: it would
  be read later as a record of what they do.

So this document covers functionality, and stops where the evidence stops. See
**What is needed to do the UI half** at the end.

## What HelloRemind sells, as far as can be established

An automated reminder *call* service aimed at the caregiver, not the senior.
Their claimed capabilities:

| Claim | Source wording |
| --- | --- |
| Phone calls and text messages | "automated phone calls and text message reminders" |
| A choice of voice | "personalized voice recordings or text-to-speech" |
| Retries, then escalation | "smart retries and automatic escalation to multiple caregivers" |
| No device required | "no app required — just a phone call they already know how to answer" |
| Tone as a feature | "warm and personal, not automated and cold" |
| Not for emergencies | "should never be relied upon for critical or emergency medical situations" |

Two of these are worth noticing beyond the feature list.

**They sell the same disclaimer Remindly does.** "Never rely on this for
emergencies" is on their marketing page, not buried in terms. Remindly reached
the same position independently — the `_critical_alert_caveat` partial, the FAQ's
refusal to say a dose was "taken" when it was only *marked done*. This is
evidence the honesty is not costing Remindly anything competitively. A paying
competitor prints it too.

**They sell warmth as the differentiator**, not features. "Warm and personal, not
automated and cold" is doing the work that a feature comparison usually does.
This is the one piece of positioning Remindly has no equivalent for, and the
cheapest thing on this page to act on.

## What Remindly already has

The phone channel is much further along than `PHONE_CALL_REMINDERS_DESIGN.md`
claims. That document's status header is out of date and has been corrected in
the same commit as this file; the detail is worth stating here because it
changes what is left to build.

| HelloRemind claim | Remindly today |
| --- | --- |
| Automated phone calls | **Built.** `VoiceReminderJob` → `TelnyxVoiceService`, driven by webhooks. Verified against a real handset. |
| Keypad response | **Built.** One DTMF digit maps onto the existing `Acknowledgement` kinds — 1 taken, 2 snooze, 3 skip. |
| Smart retries | **Built, and bounded.** `MAX_ATTEMPTS = 3`, `RETRY_AFTER = 5.minutes`, plus a per-person daily ceiling and a unique index on `(occurrence_id, attempt_number)` so two runs cannot both claim an attempt. |
| Escalation to multiple caregivers | **Built for email.** `ReminderNotificationService.notify_unanswered` mails *every* linked caregiver on each unanswered attempt of a `critical?` reminder, deliberately ignoring both category preferences and quiet hours. |
| Consent | **Built.** `call_consent_at`, `call_opted_out_at`, `call_reminders_enabled`; a verification call asks the number itself to agree, and pressing 9 on any call opts out permanently. Re-checked inside the job, not trusted from the scheduler's query. |
| Number verification | **Built.** `phone_verified_at`, `TelnyxCall.reserve_verification`, capped at five attempts per number per day. |

Calling hours are enforced in the called party's own timezone, and an
unresolvable timezone blocks the call rather than defaulting to one.

The whole channel sits behind the `phone_call_reminders` feature flag, and
production has no Telnyx credentials — so none of it is switched on.

## The real gaps

Four, in the order they are worth doing.

### 1. There is no SMS channel at all

`grep -ril "sms\|twilio\|text_message"` over `app`, `lib`, `config` and
`db/schema.rb` returns nothing. This is the largest verified functional gap, and
the cheapest to close:

- A text costs roughly a twentieth of a call and has no answering-machine
  problem, no calling-hours problem in the same acute form, and no "did a person
  or a voicemail hear this" ambiguity.
- It is the natural **escalation** channel. Today an unanswered critical dose
  emails the caregivers. Email is the wrong medium for "your mother has not
  answered three calls about her 8am dose" — HelloRemind escalates by text, and
  they are right to.
- It reaches the caregiver, who is the one holding a smartphone. The senior may
  well still want the call.

The existing `notify_unanswered` path is the correct insertion point: recipients,
deduplication and the critical-only rule are already decided there.

### 2. No answering-machine detection

Still genuinely absent — the one item the design doc's "not built" list gets
right. Without it a reminder is spoken to a voicemail greeting and the attempt is
consumed. For a product whose entire claim is "the reminder reached them", this
is the gap that makes the difference between the call working and appearing to.

Telnyx prices AMD per call, which folds into the money question below.

### 3. Text-to-speech only — no recorded voice

HelloRemind offers "personalized voice recordings **or** text-to-speech".
Remindly has only the second, on both the browser client and the phone calls.

A daughter's own voice saying "Mum, it's half eight, time for your tablets" is a
different product from a synthesised one, and it is the concrete mechanism behind
the "warm, not cold" positioning that HelloRemind leads with. It is also the
feature on this page most likely to make somebody choose one service over the
other, and it needs no new provider — an uploaded audio file played by Telnyx,
and `<audio>` on the voice page.

Note what it costs elsewhere: the app currently has no Active Storage. This adds
file upload, storage on the DigitalOcean volume, and a moderation question
nobody has asked yet.

### 4. Escalation is single-tier

Every caregiver is notified at once, by email. HelloRemind escalates — implying
an order and a delay. Worth building only after (1), because a tiered escalation
whose only channel is email is not worth the schema.

## The decision none of this can route around

`PHONE_CALL_REMINDERS_DESIGN.md` argues that calls are the first feature with a
marginal cost, estimates **$3–5 per senior per month**, and stops: nothing should
be built until the monetisation model is chosen, because the answer changes both
the schema and the copy.

**HelloRemind is the evidence that argument was waiting for.** A competitor is
charging for exactly this and describing it as a service rather than an app. That
does not decide Remindly's model, but it removes the worry that a paid reminder
call is a thing nobody buys.

SMS does not escape the problem, it only makes it cheaper — a text still costs
per message, and the homepage still says *"Free while in beta — no card, no ads,
no sales calls"* with an explicit promise that **"if charging ever becomes
necessary, you will be told first."** That sentence was written to be kept. Any
of the four gaps above ships either behind that promise being honoured, or not at
all.

## What is worth copying that costs nothing

The one recommendation here that needs no provider, no schema and no money
decision: **HelloRemind sells warmth, and Remindly sells accuracy.**

Remindly's copy is unusually careful — it will not say "taken" when it means
"marked done", and it says out loud that a browser page has to stay open. That
care is a genuine asset and should not be traded away. But read end to end, the
public pages describe a mechanism, and HelloRemind describes a feeling.

These are not in conflict. "A voice they know, at the time it matters" is both
warm and true. The homepage already has one sentence doing this — *"You cannot be
there for every tablet, every appointment, every glass of water"* — and it is the
best line on the site. There is one of it.

This is a copy direction, not a copy change. The public pages are annotated with
the reasoning behind individual sentences and several record wording that was
argued over and settled; they should not be rewritten against a competitor
nobody has seen.

## What is needed to do the UI half

The request that produced this document asked for inspiration in **UI and
functionality**. Only the second half could be attempted. To do the first, one of:

- Screenshots of HelloRemind's homepage, signup, and caregiver dashboard.
- A saved copy of the pages (`File → Save Page As`), which carries the real CSS.
- Running the work somewhere `helloremind.me` is not blocked by the egress proxy.

Without one of those, any UI work claiming their influence is fabricated.

## Suggested order

1. **Decide the money question.** It gates everything else and is not an
   engineering task.
2. **SMS**, as the escalation channel first and a reminder channel second.
3. **Answering-machine detection**, before the call channel is enabled for
   anyone who is not testing it.
4. **Recorded voice**, as the differentiator, once storage is warranted.
5. **Tiered escalation**, last, and only if families ask for it.
