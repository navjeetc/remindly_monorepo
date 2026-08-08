# Remindly marketing plan

Written 2026-07-26, revised 2026-08-08. Framework: *The Minimalist Entrepreneur*
— spend time before money, build an audience rather than buy attention.

**What changed in the 2026-08-08 revision.** Three facts arrived that the first
draft had to guess at, and each one moves the plan:

1. **Google Search Console is verified and the sitemap is submitted.** Bing is
   not. The blocking item at the top of the last draft is cleared.
2. **Track A has not started.** Zero to two households use Remindly in a normal
   week. Meanwhile Track B shipped three posts, a second printable, a top nav
   and a full structured-data pass. The last draft said *do not skip to Track B
   because it is more comfortable*, and that is precisely what happened.
3. **There is no founding story** — Remindly did not come out of the author's
   own family. The Level 2 content plan was built on that story and needs
   replacing.

And one thing arrived that is worth more than all three: **the first real
feedback on whether the site converts**, from early users. It is the top of this
document now, because it is the only evidence we have about the page that
everything else drives traffic to.

## The site feedback, and what to do about it

Five items came back. Checked against the markup, four of them are about
**sequence rather than substance** — the content is already on the page, in the
wrong order, below the fold. One is a genuine accuracy problem. In priority
order:

### 1. "Marked done" is not "taken" — fix this first

This is the only item that is not a conversion tweak. The FAQ is already
careful: it says a dose is *"marked taken"*, and the *Is Remindly a medical
device?* answer is explicit that it "cannot tell whether a tablet was actually
swallowed". The homepage is not careful. It says:

- Lead paragraph: *"it tells you when they're taken — or when they're not"*
- Meta description: *"Remindly tells you when a dose is taken or missed"*

The meta description is the sentence Google prints under the result. The most
imprecise claim on the site is the one strangers read first.

The fix is a vocabulary, applied everywhere: **"marked done"**, **"confirmed on
the device"**, **"marked taken at 8:04"**. Never "taken" unqualified, never
"confirmed" alone, nothing that reads as verification. This runs past the
marketing pages into the **notification emails**, which are the place a
caregiver actually forms the belief — an email saying "Margaret took her
morning medication" is a stronger claim than the product can support. Audit the
mailers as part of the same change.

Highest-stakes use case, lowest-cost fix, and it is the one that would matter in
a bad week.

### 2. One CTA, and one label per destination

The hero already has a single primary and a single secondary button. The
confusion is elsewhere: the nav's **"Sign in"** and the hero's **"Get started —
it's free"** point at the same `login_path` under two labels, so the page offers
what looks like three next actions for two things. The `feat/top-nav` work
already established the principle — *one label per destination* — and the
homepage is the page that breaks it.

- Primary: **"Set up reminders for my parent — free"**. Names the outcome and
  who it is for; "Get started" names neither.
- Secondary, lower emphasis: **"See how it works first"**.
- Resolve the nav duplicate rather than adding a third competing action.

### 3. Answer the setup objection above the fold

The three steps the feedback asks for are already written and already correct
(`home.html.erb`, the `ol.steps` block): you create the reminders, they hear
them spoken, you see done or missed. They sit roughly five hundred words down,
after an essay. Hoist a compact version directly under the hero, framed as the
objection it answers: **"Works with the tablet or computer they already use."**
No app, no app-store account, nothing to install.

**Setup time is stated nowhere on the site**, and it is the question behind the
objection. Do not invent a number. Time it: set up a fresh account cold with a
stopwatch, then time one of the ten people in Track A doing it without help.
Publish the real figure, rounded honestly ("about ten minutes, most of it
spent deciding what to remind them about"). If the true number is embarrassing,
that is a product finding, not a copy problem.

### 4. Show the senior's screen sooner

Also mostly a sequencing fix: the senior screenshot already appears *before* the
caregiver one, which is the right instinct. It is just buried. Move it up so the
first image on the page is the spoken prompt, the large **Done** button and
**Snooze**, and caption it with the line the feedback proposes:

> No app to learn. Just a familiar screen that speaks when it's time.

The buyer is the adult child, but the objection that stops them is *"my mother
will never use this."* That objection is answered by a picture, not a paragraph.

### 5. Reassurance next to "free"

The *"Why is Remindly free — what's the catch?"* FAQ answer already exists and
is good. What is missing is one line where the claim is made, in the hero. The
current note sells "no limit on how many reminders" — a feature nobody is
worried about. Replace with the three things a caregiver is actually braced for:

> **Free — no card, no ads, no sales calls.**

All three are true today, which is the only reason to print them.

### The one to schedule, not ship

The closing suggestion — **assemble a beta group, gather feedback, record
testimonials** — is the most valuable line in the whole review, and it cannot be
built this week because it requires Track A to exist first. It is also the
answer to the founding-story problem below. It becomes the spine of the next 90
days.

## Where we actually are

The minimalist playbook says to start marketing after ~100 paying customers,
because marketing is sales at scale and you cannot scale something that has not
worked once. Remindly is not there. It is free, it is early, and the number of
households using it weekly is between zero and two.

Two tracks, as before — but the balance has to change:

- **Track A — get to 50 households, by hand.** One-to-one, unscalable on
  purpose. **This has not started.** It is now roughly all of the work.
- **Track B — the compounding assets.** SEO and the email list are planted.
  Google is indexing. They now need *time*, not more input.

The honest read on the last two weeks: Track B is finished enough. A fourth,
fifth and sixth blog post added to a site with two users compounds nothing —
posts rank on a timescale of months regardless of how many there are, and three
is already enough to find out whether any of them can rank at all. Writing more
now is the comfortable move that feels like progress.

## The free decision

Free is not just a price here, it is the distribution strategy.

The communities where the people who need Remindly gather — r/AgingParents,
r/CaregiverSupport, AgingCare forums, local senior centres — are hostile to
product promotion and right to be. Caregivers are a heavily marketed-to,
frequently exploited group. A free tool with no card field and no trial is the
one thing that can be mentioned in those rooms without it reading as a pitch,
and it is the only reason a moderator lets it stand.

The site says so plainly, and says it in a way that does not trap us: free
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

This is the plan now. Do these in order.

1. **Fix the five site items above**, because the next ten people will land on
   that page and the feedback says what they will trip over.
2. **Write down the ten people you already know** with a parent living alone.
   Not prospects — people you can text. Ask them to try it, watch them set it
   up, and **say nothing while they do**. Every place they hesitate is a bug.
   Time the setup while you are there.
3. **Sit with three seniors** using the voice page for a week. The "page must
   stay open" limitation is the one most likely to kill this quietly. Find out
   whether it does.
4. **Form the beta group** out of whoever survives steps 2 and 3 — six to ten
   households is plenty. Give it a name, email them monthly, and tell them
   plainly that they are early and their complaints set the roadmap. This group
   is simultaneously the product feedback loop, the testimonial source and the
   Level 2 content supply.
5. **Ask for testimonials once, at the right moment** — not at signup, but after
   a household has used it for three or four weeks. Ask for the specific thing:
   *what did you stop doing since you started using this?* Record with explicit
   written permission, first name and city only, and offer to show them the
   quote before it goes up.
6. **Go where they already are, as a member.** r/AgingParents,
   r/CaregiverSupport, AgingCare.com forums, a local senior centre or Area
   Agency on Aging. Four weeks answering caregiving questions without mentioning
   Remindly at all. Then mention it only as a direct answer to a question
   somebody asked.
7. **Talk to one hospital discharge planner or social worker.** They meet this
   exact family at the exact moment of need, every day. If Remindly is worth
   anything, one of them will tell you why it is not.

**Day-30 gate: ten households.** If ten people you already know will not use a
free tool built for a problem they have, the problem is the product or the
pitch, and no amount of Track B fixes it. That finding is worth more than
another quarter of posts.

**Day-90 target: 50 households in a normal week.**

## Track B: SEO — now in maintenance

### Shipped

- `/faq` with `FAQPage` structured data; `SoftwareApplication` declaring price 0;
  `Organization`, `WebSite` and `Article` graphs
- `/sitemap.xml` generated from routes and posts, advertised in `robots.txt`
- `og:image` + `twitter:card`
- `/blog` with three posts (26–29 July); publishing is adding a Markdown file,
  and a future `published_on` is a draft
- Two ungated printables: `/routine_sheet`, `/caregiver_checklist`
- Mailing list with welcome + admin notification, all mail from
  `hello@remindly.care`
- Top nav: How it works · FAQ · Blog · Sign in
- **Google Search Console verified, sitemap submitted**

### The three things left, and then stop

1. **Bing Webmaster Tools.** Fifteen minutes. Bing skews older than Google,
   which for this audience is not a rounding error.
2. **Check that the three posts are actually indexed.** Two weeks after a
   submitted sitemap, Search Console's coverage report gives a real answer. Zero
   indexed pages after a submitted sitemap is a technical fault worth finding
   now, not in November.
3. **Read the query report monthly.** The queries people actually type will not
   match the table below. That list is worth more than any keyword tool, and it
   is the only input that should trigger writing another post.

### The queries written for

| Query | Page |
|---|---|
| how to remind elderly parent to take medication | published |
| medication reminder for elderly parent living alone | published |
| what to check on daily when a parent lives alone | published |
| free medication reminder app for seniors | homepage + FAQ |
| how do I know if my mom took her medication | published |
| reminder system for elderly with memory loss | unwritten |
| how to help a parent who lives alone remember things | unwritten |

Per the editorial direction already set: **no product comparisons, no
recommending competitors.** The talking-clock post was rewritten as generic
caregiving advice for exactly this reason, and that decision stands.

## Content: educate, inspire, entertain

### Level 1 — Educate

Five, in priority order. One a month at most, and only if Track A is moving.

1. **"What do I need at their end, and how long does setup take?"** The long
   form of the objection panel. Doubles as the honest answer to the search
   *how to set up a tablet for an elderly parent* — font size, auto-lock, keeping
   a screen awake, keeping a page open. Turns the product's biggest limitation
   into a genuinely useful general how-to.
2. **"When a parent says they don't need help."** The most common conflict in
   every caregiving forum, and it sits directly upstream of the patronising
   phone call the product exists to end.
3. **"Sharing the care with siblings without it turning into an argument."**
   Maps to `CaregiverLink` and shared tasks, which currently have no story told
   about them anywhere.
4. **"What to bring to a parent's doctor appointment."** Printable-shaped —
   becomes the third ungated sheet and feeds the list.
5. **"Signs it is time for more help at home."** High intent, hard question, and
   the honest answer is sometimes "more than a reminder app". Saying so is what
   makes the other four believable.

### Level 2 — Inspire, without a founding story

There is no family origin to tell. Inventing one is out of the question, and a
manufactured mission statement reads as exactly what it is. The replacement is
**other people's stories plus radical transparency** — and the beta group is
what produces the first kind.

1. **Beta-user stories.** The single strongest asset available. *"I stopped
   ringing my mother at nine every morning"* in a real person's words beats any
   founder narrative, and unlike a founding story it compounds — every new
   household is another one.
2. **"Why Remindly is free, and what would have to change that."** A dated,
   public commitment. Free products are assumed to have a catch; the only cure
   is specificity about the conditions.
3. **"What our privacy policy actually means."** The public pages set no
   analytics cookies and log no IPs. Almost nobody in this category can say
   that, and most of the competition is worse than the reader fears. This is the
   trust asset that stands in for the family story — and it is already true, so
   it costs a post rather than a project.
4. **"The page has to stay open."** Name the limitation before a user discovers
   it. Doing this in public is the cheapest credibility available, and it is
   already the tone of the FAQ.
5. **An interview with a discharge planner or home-care nurse.** Their words,
   your platform, their name if they will give it. The emotional weight of a
   founding story, borrowed honestly from someone who has earned it.

### Level 3 — Entertain

Skip it, and this is a deliberate deviation from the framework rather than an
oversight. Entertainment reaches furthest and is hardest to land, and caregiving
humour from a stranger with a product goes wrong more often than it goes right.
Padding this list to five would produce four things that should never ship. Two
that could work, at 500 users, not now:

1. **The nine-in-the-morning phone call, told from the parent's side.** The
   pattern-break is that the parent finds the call as unbearable as the caller
   does. It is funny because both people are being kind and both are miserable.
2. **A short video of the setup, unedited, mistakes left in.** Entertaining in
   the way competence is entertaining, and it doubles as the setup-time proof
   from Track A item 3.

## Email: the owned channel

Subscribers compound; followers do not, and a subreddit can change its rules on
a Tuesday.

- **The offer:** two printable sheets — a daily routine sheet and a caregiver
  checklist — useful whether or not anyone ever uses Remindly. **Deliberately
  ungated.** Gating them would collect more addresses in the short run and trade
  away pages that can rank on their own, plus the goodwill of a group that is
  used to being milked for an address before anyone helps them.
- **Where:** homepage, blog index, every post, and the sheets themselves. Each
  form records its `source`, so in a few months that column answers "which
  writing is worth doing more of" without guessing.
- **What to send:** monthly, short, one useful thing about caring for a parent at
  a distance plus one line on what changed in Remindly.

Two things to settle before the first send:

- **The path has never fired with a real address.** `deliver_later` → Solid
  Queue → Postmark did nothing in production until PR #41. One live signup with
  a readable inbox, and one magic-link login, before anything is announced. See
  `docs/POST_DEPLOY_CHECKS.md`.
- **Do not start a monthly newsletter for eleven subscribers.** Hold until ~25,
  or until the beta group exists — the beta group email *is* the newsletter,
  earlier and better, because those people asked for it by name.

There is no unsubscribe link, by design: replies come to a human at this size.
That stops being acceptable somewhere around a few hundred subscribers, and that
is also roughly where bulk-sender rules begin requiring one-click unsubscribe.
Revisit before the list gets there.

## Build in public

Two accounts, as the framework says: you the person, and Remindly the product.
Pick **one** platform and stay there.

The last draft named Facebook, on the grounds that adult children of aging
parents are there. That is true and still not the right answer, for one reason:
**Facebook group posts are invisible to search.** A good answer written in a
Facebook group helps one person and then disappears. The same answer on Reddit
is indexed, ranks for the long-tail question that prompted it, and is still
bringing people three years later — which is the same compounding that makes the
blog worth having, at a fraction of the effort.

So: **Reddit, as a member, under Track A rules.** r/AgingParents and
r/CaregiverSupport. Four weeks contributing with no mention of the product. This
is not a second channel bolted onto Track A; it is Track A step 6, and the
audience-building is a side effect of doing the sales work honestly.

Developer platforms are for peers and encouragement. That is a different goal —
do not let activity there feel like progress on this one.

## Paid advertising

Not yet, and the case is stronger than it was. Revisit only when all three hold:

1. Track A cleared 50 weekly households
2. Organic search brings visitors without being pushed
3. You know what a signed-up caregiver is worth

The third remains the blocker: on a free product a customer is worth $0 in
revenue, so there is no honest number to compare a click price against. Buying
traffic to a page that two households have successfully used would be spending
real money to scale something not yet shown to work once. Until there is a paid
tier, the answer is no, and the money is better spent on the people already
using it.

## The next 90 days

| Weeks | Track A — the work | Track B — maintenance only |
|---|---|---|
| 1–2 | Ship the five site fixes, accuracy first. Text the ten people. Watch them set it up; time it. | Bing Webmaster Tools. Confirm the three posts are indexed. |
| 3–4 | Sit with three seniors for a week. Publish the real setup time. | Nothing. |
| 5–8 | Form the beta group. Monthly note to them. Join two communities; contribute only. | Post 4 — the setup/device post. First Search Console query read. |
| 9–12 | Ask the first testimonials. Talk to one discharge planner. Answer where relevant; mention Remindly only as an answer. | Put two testimonials on the homepage. Post 5, only if the query report justifies it. |

Review at 90 days against one number: **households using Remindly in a normal
week.** Not signups, not visitors, not impressions.

## Open questions

1. ~~What is the founding story?~~ **Answered 2026-08-08: there isn't one.**
   Level 2 now runs on beta-user stories and transparency instead.
2. **Which community do you already belong to?** Still unanswered, and still the
   weakest point in the plan. It assumes none, which is the hardest starting
   position. If you do belong to one, Track A reorders around it.
3. **Is free permanent, or free until it costs too much to run?** The copy
   survives either answer, but it decides whether paid acquisition ever becomes
   a question worth asking.
4. **What is the real setup time?** Nobody has measured it. It is the first
   objection, it is unanswerable from the code, and one stopwatch settles it.
