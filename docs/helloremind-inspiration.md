# HelloRemind as a model for Remindly

**Purpose:** work out what Remindly should take from HelloRemind
(`helloremind.me`), which is building the product Remindly gives away:
automated reminder calls for an older person, set up by the family who care for
them.

## What this is based on

Two mobile screenshots of their homepage, supplied 2026-09-11, plus
search-index summaries of their `/about` and `/help` pages. The site itself is
blocked by the network egress proxy here, so nothing below comes from browsing
it.

That is enough for the homepage's design language and its top-of-funnel copy,
which is what the UI recommendations rest on. It is **not** enough for the
signed-up product: no signup flow, no caregiver dashboard, no pricing page, and
no call has been seen. Anything about how their app behaves after the trial
starts is unknown and is not guessed at here.

## The single most important correction

**HelloRemind has not launched.** Both calls to action on the homepage — the
nav button and the hero button — read **"Coming Soon"**. Beside the hero button:
*"14 days free · no credit card"*.

An earlier revision of this document said a competitor was *charging* for
reminder calls and treated that as demand evidence for Remindly's deferred
monetisation decision. That was wrong, and it was the load-bearing claim, so it
is corrected here rather than quietly edited: they have announced a trial and a
price, and have no customers. What their existence establishes is that somebody
else looked at this market and concluded a subscription was the model. It
establishes nothing about whether families buy.

`PHONE_CALL_REMINDERS_DESIGN.md`'s monetisation gate therefore stands exactly
where it stood. Nobody has validated this price.

## Their positioning, verbatim

| Slot | Copy |
| --- | --- |
| Eyebrow | "A DAILY CALL, NOT AN APP" |
| H1 | "Know they're okay — *without asking*." |
| Sub | "Automated reminder calls your loved one will answer, plus real-time updates straight to you. The phone she already has. Nothing for her to learn." |
| Pull-quote | "Every morning I wake up wondering, 'Did Dad take his pills?'" |
| Under it | "You shouldn't have to choose between hovering and not knowing. HelloRemind makes the call, hears the answer, and tells you. You get to go back to being family." |
| Section head | "How a reminder becomes relief" |
| Sub | "Four steps · about two minutes to set up" |

Three things are worth taking from this and one is worth refusing.

**They name the feeling, not the mechanism.** "Know they're okay", "becomes
relief", "go back to being family". Remindly's homepage describes what the
software does and is unusually careful about it; HelloRemind describes what the
caregiver gets back. These are not in conflict — Remindly's own best line,
*"You cannot be there for every tablet, every appointment, every glass of
water"*, already does it. There is one of it.

**They put a number on setup.** "about two minutes". Remindly's homepage
deliberately refuses to, and the comment above that copy says why: nobody has
timed it, and inventing a number on the page a caregiver trusts with their
parent's medication is not a copy decision. That refusal is right. **Time the
setup, then say it** — this is the cheapest conversion win available and it is
blocked only on a stopwatch.

**They sell the absence of a device as the headline**, not as a reassurance
further down. "A DAILY CALL, NOT AN APP". "Nothing for her to learn."

**What to refuse:** "Automated reminder calls your loved one *will answer*". No
service can promise that, and the same page elsewhere admits it is not for
critical situations. Remindly's copy standard — it will not say a dose was
"taken" when it means "marked done" — already rules this sentence out.

## Their design language

Observed from the two screenshots.

| | |
| --- | --- |
| Ground | warm cream, roughly `#f7f3ec` — not white |
| Cards | white, on the cream, radius ~24px |
| Accent | salmon/coral, roughly `#e8806b`, on fully-rounded pill buttons |
| Highlight | pale yellow, as a glow behind the hero card and as a row tint |
| Dark band | warm near-black, roughly `#2b2724`, full-bleed between cream sections |
| Display type | a serif, large, regular weight — headings and pull-quotes |
| Body type | a sans, generous line height |
| Italic serif | reserved for **anything spoken aloud** |
| Metadata | separated by a middle dot: "Morning meds · daily 9:00 AM" |

The whole thing reads domestic rather than clinical. That is the argument: this
is a product about your mother, not about a patient.

**Their accent fails contrast.** White text on `#e8806b` measures **2.9:1** —
under WCAG AA for any text size. Remindly puts seniors in front of these pages
and ships a per-user text scale, so it cannot copy that. The implementation
below uses a deeper terracotta measured at 5.2:1 on cream and 5.7:1 for white
on the accent.

### The idea worth stealing outright

**The hero transcript.** Under their headline sits a white card showing a call
as a chat transcript: *"Ruth's kitchen phone · 9:00 AM"*, subtitled *"the same
phone she's answered for forty years"*, then a dark right-aligned bubble —
*"Hello?"* — and a pale left-aligned one — *"Good morning, Ruth. Time for your
heart pills."*

This solves the problem Remindly's marketing site has always had. Everything
this product does happens out loud in somebody's kitchen. A web page can only
ever *assert* that, and the homepage's paragraphs are all assertions about a
sound. A transcript is the one way to put a spoken product on a screen.

Implemented on the homepage in this change — see below.

## Functional gaps

Verified against the code, not assumed.

### 1. No SMS anywhere

`grep -ril "sms\|twilio\|text_message"` over `app`, `lib`, `config` and
`db/schema.rb` returns nothing. Largest gap, cheapest to close, and the natural
**escalation** channel: today an unanswered critical dose emails every linked
caregiver, and email is the wrong medium for "your mother has not answered
three calls about her 8am dose". `ReminderNotificationService.notify_unanswered`
is the insertion point — recipients, deduplication and the critical-only rule
are already decided there.

### 2. No answering-machine detection

A reminder spoken to a voicemail greeting consumes an attempt and looks
delivered. For a product whose claim is "the reminder reached them", this is the
difference between working and appearing to. Telnyx prices AMD per call, so it
folds into the money question.

### 3. Check-ins are not a distinct thing

Their sample schedule lists three items, and the third is highlighted:

> Morning meds · daily 9:00 AM
> Dr. Patel visit · Thu 2:00 PM
> **"Are you OK?" · Sundays**

That is not a task reminder. It is a recurring welfare check whose *answer* is
the payload — there is nothing to mark done. `competitor-gap-action-plan.md`
already lists scheduled check-ins as a gap ("distinct from task reminders",
"support a check-in window rather than requiring an exact minute"); a second
competitor leading with one is corroboration.

Remindly can express this today only as a reminder somebody marks done, which
records the wrong fact.

### 4. Text-to-speech only

They offer "personalized voice recordings **or** text-to-speech". A daughter's
own voice is the concrete mechanism behind the warmth they sell, and it needs no
new provider — an uploaded file played by Telnyx, and `<audio>` on the voice
page. It does need Active Storage, which the app does not currently have, plus a
moderation question nobody has asked.

### 5. Escalation is single-tier

Every caregiver is notified at once, by email. Theirs implies an order and a
delay. Worth building only after SMS — a tiered escalation whose only channel is
email is not worth the schema.

## What Remindly already has

`PHONE_CALL_REMINDERS_DESIGN.md` understated this badly; its status header has
been corrected in the same branch. Calls, keypad acknowledgement, three bounded
retries, per-day call ceilings, consent (including keypad opt-out), number
verification, and multi-caregiver alerting on unanswered critical doses are all
built. The channel is behind the `phone_call_reminders` flag and production has
no Telnyx credentials, so none of it is on.

**A thing to check:** the homepage and meta description already tell readers
Remindly will telephone a parent who has no tablet. If production genuinely
cannot place calls, that copy is promising a channel that is switched off.

## What was implemented in this change

UI only, and no existing sentence was rewritten. The public copy is annotated
with the reasoning behind individual phrasings and several record wording that
was argued over and settled; it is not for redecorating against a competitor.

- **The marketing palette moved from cool blue on white to the warm cream,
  terracotta and pale-yellow system above.** Every pair measured against AA and
  recorded in the CSS: ink 14.7:1, muted 6.8:1, accent 5.2:1, white-on-accent
  5.7:1, ink-on-highlight 13.5:1, dark band 14.8:1.
- **Serif display type for headings**, sans for body. System fonts only —
  this layout loads nothing third-party on purpose, so their exact face cannot
  be matched; Georgia is the one real serif present effectively everywhere.
- **Pill buttons and larger card radii.**
- **The hero transcript**, showing the real exchange: the tablet speaks, the
  senior presses the green ✓ Done the voice client actually renders, and the
  caregiver's email arrives. It closes by saying Remindly knows the button was
  pressed and cannot know whether the tablet was swallowed — the claim the rest
  of the site is careful about, stated in the one place it would be easiest to
  overclaim by implication.

The transcript is deliberately the tablet, not a phone call: the phone channel
is switched off in production, and a homepage picture of a working call would be
advertising it.

## Suggested order

1. **Time the setup and put the number on the page.** A stopwatch.
2. **Decide the money question.** Unchanged by any of this — they have no
   customers either.
3. **SMS**, as the escalation channel first and a reminder channel second.
4. **Check-ins** as a first-class type, with a window rather than a minute.
5. **Answering-machine detection**, before calls are enabled for anyone who is
   not testing them.
6. **Recorded voice**, once storage is warranted.
7. **Tiered escalation**, last, and only if families ask.
