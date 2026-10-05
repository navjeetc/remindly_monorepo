# Outreach templates

Messages for reaching people who might use Remindly or point families to it,
one audience per section. Each is written to be sent as it stands, after
filling in the brackets and personalising one line.

**Keep it true.** Every claim about the product comes from
`docs/ONBOARDING_FEATURES.md`, which lists only what is live in production. A
PR that changes or removes a feature checks this file as well as that one. The
personal lines (why Navjeet built it, where he lives) are his to keep or
change.

**Send personally.** From Navjeet's own address, one recipient at a time. Never
through Postmark, which carries the sign-in links and forbids unsolicited mail,
and never through GoHighLevel, whose sub-account is shared with other
businesses: complaints there would land on all of them. Volume outreach, if it
ever happens, needs its own sending domain and a tool built for it.

**Tag the links.** Each audience has its own `?from=` tag, so a visit it brings
shows on Admin → Traffic. Tags must match `PageCount::SOURCE_FORMAT`
(lowercase letters, digits, `-` and `_`, up to 40 characters, starting
with a letter or digit). Anything else is silently dropped and the visit is
counted untagged.

**The law (CAN-SPAM).** These are commercial emails: they promote Remindly.
The FTC's guidance is explicit that the law covers *every* commercial email,
including one sent to a single person and one sent to a business; there is no
one-to-one or business-to-business exception. So every email here must have:

- an honest From line and a subject that isn't misleading;
- **a valid physical postal address** for the sender: a street address, a
  P.O. box, or a registered private mailbox (use one of the last two rather
  than a home address);
- **a clear way to opt out**, honoured within **10 business days**, and never
  written to again after;
- nothing that hides it is promotional.

The templates below carry the address and the opt-out line; don't trim them
off when sending. The voicemail and the printed explainer are not emails, but
keep the opt-out promise there too: anyone who says no is not contacted again.
Keep a note of who opted out. See
https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business.

No phone numbers or addresses in this file: `[phone number]` and
`[postal address]` stay placeholders.

---

## Home care agencies

**Why agencies.** They already serve the families Remindly is for, and
Remindly covers the hours between their caregivers' visits. One agency that
finds it useful can introduce many families. Start local: 15–20 agencies
around Loudoun County, contacted one at a time, with an offer to set it up
free for one or two of their clients.

**Tag:** `?from=agency`

### First email

**Subject:** A free tool for your clients' families, from a neighbour in Ashburn

Alternatives: "Between-visit reminders for your clients, free" · "Quick
question about your clients between shifts"

> Hi [first name, or "there"],
>
> My name is Navjeet. I live in Ashburn, and I built a small service called
> Remindly after struggling to keep my own parents on track with medication
> while I couldn't be there.
>
> It covers the hours between your caregivers' visits. At the time a dose or
> task is due, Remindly rings the client's own phone, landline or mobile, and
> says the reminder out loud. They press 1 when it's done. For medication, the
> family is emailed when a dose is marked done, and again if the time passes
> and nobody marks it, so nobody has to ring round to check.
> The first call only asks the client's permission and says who set it up;
> no reminder calls come until they agree.
>
> It's free while in beta, with no app for the client to learn.
>
> I'm not trying to sell you anything. I'd like to set it up, free and myself,
> for one or two of your clients whose families worry about the gaps between
> visits, and hear honestly whether it helps. Would you have 15 minutes in the
> next week or two? I'm happy to come by.
>
> There's an 11-minute walk-through here if you'd like to see it first:
> www.remindly.care/how_to?from=agency#videos
>
> Thanks for reading,
> Navjeet Chabbewal
> [phone number]
> www.remindly.care/?from=agency
>
> Remindly · [postal address]
> If you'd rather not hear from me again, reply "no thanks" and I won't write
> again.

Personalise one line per agency (the area they serve, something from their
site). It is the difference between being read and being skipped.

### Follow-up

About a week later, once, if there is no reply:

> Hi [name], just floating this back up in case it got buried. Happy to drop by
> for 15 minutes, or to send a one-page summary you could pass to a family.
> Either way, thanks. Navjeet
>
> Remindly · [postal address]
> If you'd rather not hear from me again, reply "no thanks" and I won't write
> again.

Don't send it to anyone who replied "no thanks" to the first email.

### Voicemail

About 20 seconds:

> "Hi, this is Navjeet, I live locally in Ashburn. I've built a free service
> that phones older people at home when a medication or task is due, and tells
> their family if a dose is missed: it covers the time between your caregivers'
> visits. I'd love 15 minutes to show you, and set it up free for a client or
> two. My number is [phone number]. Thanks!"

### One-page explainer

To leave behind after a visit, attach to the follow-up, or hand to a family.
Fits on one printed page.

> # Remindly
> ### Reminders that reach your client between visits
>
> Your caregivers can't be there every hour. Remindly covers the time in
> between: it phones your client at home when something is due, and tells the
> family whether it was done.
>
> **How it works**
>
> 1. **The family sets it up** from their own phone or computer: morning
>    tablets, a glass of water, Thursday's appointment. Reminders repeat daily
>    or weekly, on the client's clock.
> 2. **Remindly calls the client's own phone**, landline or mobile, at the
>    right time and says the reminder out loud. They press 1 when it's done, or
>    2 to be reminded again shortly. Nothing to install, nothing to read.
> 3. **The family hears what happened.** For medication, they get an email when
>    a dose is marked done, and another if the time passes and nobody marks it.
>    For reminders where being late matters, they're told as soon as the first
>    call goes unanswered.
>
> **Safe by design**
>
> - **No reminders without the client's agreement.** The first call only asks
>   permission, and says who set it up. Reminder calls start only once they
>   agree.
> - **The client stays in control.** Pressing 9 on any call stops the calls.
>   Calls happen only in the hours the family picks, between 6am and 10pm the
>   client's time.
> - **US and Canada numbers.**
>
> **If there's a tablet in the house**, Remindly can speak from its screen
> instead, with one big Done button. No password or account for the client.
>
> **Several family members can share it**, each choosing which reminders they
> hear about.
>
> **Free while in beta.** No card, no ads, and no trial that quietly ends.
>
> **See it work:** an 11-minute walk-through at
> www.remindly.care/how_to?from=agency#videos
>
> **Questions, or want it set up for a client?** Navjeet Chabbewal ·
> [phone number] · hello@remindly.care · www.remindly.care/?from=agency
