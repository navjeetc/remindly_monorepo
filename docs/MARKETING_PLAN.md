# Remindly marketing plan

Written 2026-07-26. Framework: *The Minimalist Entrepreneur* — spend time before
money, build an audience rather than buy attention.

## Where we actually are

The minimalist playbook says to start marketing after ~100 paying customers,
because marketing is sales at scale and you cannot scale something that has not
worked once. Remindly is not there. It is free, it is early, and the number of
households using it weekly is small.

So this is not a marketing plan in the "turn on the megaphone" sense. It is two
tracks running at once:

- **Track A — get to 50 households, by hand.** One-to-one. Unscalable on
  purpose. This is where the product learns what it is.
- **Track B — plant the compounding assets now.** SEO and an email list take
  three to six months to return anything, which is exactly why they cannot wait
  until Track A finishes.

Track A is the real work. Track B is done in the background because of the lag.

## The free decision

Free is not just a price here, it is the distribution strategy.

The communities where the people who need Remindly gather — r/AgingParents,
r/CaregiverSupport, AgingCare forums, local senior centres — are hostile to
product promotion and right to be. Caregivers are a heavily marketed-to,
frequently exploited group. A free tool with no card field and no trial is the
one thing that can be mentioned in those rooms without it reading as a pitch,
and it is the only reason a moderator lets it stand.

The site now says so plainly, and says it in a way that does not trap us: free
today, and if that changes, existing users hear it first and well beforehand.
Nothing in the copy promises free forever.

## Who this is for

Not "seniors". The buyer and the user are different people, and the marketing is
aimed entirely at the buyer:

**An adult child, 45–65, who does not live with their parent.** Their parent is
managing alone but slipping — a missed tablet, a forgotten appointment. They are
phoning daily to ask "did you take it?", the parent finds the question
patronising, and both of them hate the call. They are not looking for a health
app. They are looking for a way to stop having that conversation.

Every piece of copy should be recognisable to that person in the first sentence.

## Track A: the first 50 households

Do these in order. Do not skip to Track B because it is more comfortable.

1. **Write down the ten people you already know** who have a parent living
   alone. Not prospects — people you can text. Ask them to try it, watch them
   set it up, and say nothing while they do. Every place they hesitate is a bug.
2. **Sit with three seniors** while they use the voice page for a week. The
   "page must stay open" limitation is the one most likely to kill this quietly.
   Find out whether it does.
3. **Go where they already are, as a member.** r/AgingParents and
   r/CaregiverSupport, AgingCare.com forums, a local senior centre or Area
   Agency on Aging. Spend four weeks answering questions about caregiving
   without mentioning Remindly at all. Then mention it only when it is a direct
   answer to a question someone asked.
4. **Talk to one hospital discharge planner or social worker.** They meet this
   exact family at the exact moment of need, every day. If Remindly is worth
   anything, one of them will tell you why it is not.

Target: **50 households using it in a normal week** before spending a day on
scale. If Track A stalls, the answer is a product problem, and no amount of
Track B fixes it.

## Track B: SEO

This is the highest-leverage channel for this product, because the demand
already exists as search volume. Nobody searches for "Remindly", but a great
many people search for the problem, at 11pm, after a bad phone call.

### Already shipped

- `/faq` — a real page answering the questions people type, with FAQPage
  structured data so answers can surface directly in results
- `SoftwareApplication` structured data declaring price 0, which is what lets a
  result carry a "free" label
- `/sitemap.xml`, generated from the routes, advertised in `robots.txt`
- `og:image` + `twitter:card`, so shared links stop rendering as grey boxes
- "Free to use" in the title, meta description, CTA and a "What it costs" section

### Manual step, do this first — nothing else matters until it is done

Verify `www.remindly.care` in **Google Search Console** and submit
`https://www.remindly.care/sitemap.xml`. Do the same in Bing Webmaster Tools.
Until this happens the site is essentially invisible, and no amount of content
changes that. It takes fifteen minutes.

Then check Search Console monthly for which queries actually bring people —
that list is worth more than any keyword tool, and it will not match the guesses
below.

### The queries to write for

Long-tail, low-competition, high-intent. Nobody with a marketing budget is
bidding on these because they do not convert to a paid product — which is
exactly why a free one can own them.

| Query | Page |
|---|---|
| how to remind elderly parent to take medication | blog post |
| medication reminder for elderly parent living alone | blog post |
| free medication reminder app for seniors | homepage + FAQ |
| how do I know if my mom took her medication | blog post |
| talking reminder clock for seniors | comparison post |
| Reminder Rosie alternative | comparison post |
| reminder system for elderly with memory loss | blog post |
| how to help a parent who lives alone remember things | blog post |

The **"Reminder Rosie alternative"** angle deserves attention. There is an
established hardware category — talking reminder clocks, day clocks — selling at
$70–150. People search for those products by name. A free software alternative
that runs on a tablet they already own is a genuinely useful answer to that
search, and a comparison page is honest as long as it says where the hardware is
better (it does not need a tab left open; it survives a wifi outage).

### What to write

Six posts, one every two weeks, three months. Each answers a question a
caregiver actually asks, and each is genuinely useful to someone who never signs
up. Product mention at the bottom, once.

This needs a `/blog` — currently there is nowhere for these to live. That is the
next build task if this plan is approved.

## Content: educate, inspire, entertain

**Level 1 — Educate.** The six SEO posts above are level 1. Add: what you
learned building this, from the technical side, published where developers read
it. Two audiences, two accounts, no crossover.

**Level 2 — Inspire.** The strongest asset here is the story of why this exists,
and I do not know it — whether Remindly came out of your own family, and what
the moment was. If it did, that story is worth more than all six SEO posts
combined, because it is the one thing a competitor cannot copy and the one thing
that makes a stranger trust a free tool that wants their parent's medication
schedule. If it is too personal to publish, that is a legitimate answer, and
Track B leans harder on Level 1.

**Level 3 — Entertain.** Skip it. Entertainment is the widest-reaching content
and the hardest to do, and caregiving humour lands badly from a stranger with a
product. Revisit at 500 users.

## Email: the owned channel

Start collecting now, before there is anything to send. Subscribers compound;
followers do not, and a subreddit can change its rules on a Tuesday.

- **The offer:** a printable one-page daily routine sheet — medication times,
  meals, contacts — that a family can stick on the fridge. Useful whether or not
  they ever use Remindly, which is the point. That is worth an email address in
  a way "subscribe to our newsletter" is not.
- **Where:** homepage and every blog post.
- **What to send:** monthly, short, one useful thing about caring for a parent
  at a distance, plus one line on what changed in Remindly. Same educate /
  inspire split as above.

This needs building — there is no email capture and no list. Second build task
after `/blog`.

## Build in public

Two accounts, as the framework says: you the person, and Remindly the product.
Pick **one** platform and stay there. Given the audience, the honest answer is
that adult children of aging parents are on Facebook, and Facebook caregiver
groups are where they gather — not Twitter/X, which is where founders gather.

If the goal is users, that means Facebook groups, joined as a member, under
Track A rules. If the goal is peers and encouragement, it is a developer
platform. These are different goals; do not confuse activity on the second for
progress on the first.

## Paid advertising

Not yet. Revisit only when all three are true:

1. Track A cleared 50 weekly households
2. Organic search brings visitors without being pushed
3. You know what a signed-up caregiver is worth

The third one is the problem: on a free product, a customer is worth $0 in
revenue, so there is no honest number to compare a click price against. Paid
acquisition for a free product spends real money to buy something you cannot
value. Until there is a paid tier, the answer to "should we run ads" is no, and
the money is better spent on the people already using it.

## The next 90 days

| Weeks | Track A | Track B |
|---|---|---|
| 1–2 | Ten people you know. Watch them set it up. | **Search Console + sitemap submitted.** |
| 3–4 | Sit with three seniors for a week. | Build `/blog` + email capture. |
| 5–8 | Join two caregiver communities. Contribute only. | Posts 1–2 (medication reminders; knowing if they took it). |
| 9–12 | Answer where relevant; mention Remindly only as an answer. | Posts 3–4 (Reminder Rosie alternative; memory loss). Check Search Console for real queries. |

Review at 90 days against one number: **households using Remindly in a normal
week.** Not signups, not visitors, not impressions.

## Open questions

1. What is the founding story — did this come from your own family?
2. Which community do you already belong to? The plan assumes none, which is the
   weakest starting position; if you have one, it changes the order of Track A.
3. Is free permanent, or free until it costs too much to run? The copy is written
   to survive either answer, but it changes when to think about ads.
