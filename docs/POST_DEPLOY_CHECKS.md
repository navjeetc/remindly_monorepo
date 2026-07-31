# Post-deploy checks

Things that pass in CI and still fail in production. Each one here has either
already happened in this project or is a near miss that specs cannot catch.

Run the automated block after every deploy. Run the manual block after a deploy
that touched mail, printables, or the voice page.

## Automated — a couple of minutes

```bash
# Pages answer, and the sitemap is the shape Search Console expects
for p in / /how_to /faq /routine_sheet /caregiver_checklist /blog /privacy /terms; do
  printf "%-24s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' https://www.remindly.care$p)"
done
curl -sI https://www.remindly.care/sitemap.xml | grep -iE '^HTTP|content-type'

# Every URL in the sitemap serves 200 directly. A redirect here is reported
# as an error in Search Console.
for u in $(curl -s https://www.remindly.care/sitemap.xml | grep -o '<loc>[^<]*' | sed 's/<loc>//'); do
  printf "%-3s %s\n" "$(curl -s -o /dev/null -w '%{http_code}' "$u")" "$u"
done

# Public pages must record no analytics visit. Send a browser User-Agent:
# Ahoy skips suspected bots, so a check without one passes regardless.
cd backend && bundle exec kamal app exec --reuse 'bin/rails runner "puts Ahoy::Visit.count"'
curl -s -o /dev/null -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" https://www.remindly.care/faq
bundle exec kamal app exec --reuse 'bin/rails runner "puts Ahoy::Visit.count"'   # must not have moved

# Mail is configured the way it is supposed to be
bundle exec kamal app exec --reuse 'bin/rails runner "
  puts ApplicationMailer.default[:from]
  puts ApplicationMailer.admin_recipient
"'
```

Expected: all 200; `application/xml`; visit count unchanged; sender
`Remindly <hello@remindly.care>`; recipient the configured admin address.

## Manual — the ones nothing can check for you

### 1. A real signup, with a real address

The whole path — form, `Subscriber`, `deliver_later`, Solid Queue, Postmark —
has never been exercised end to end under the current sender. Sign up at
<https://www.remindly.care/> with an address you can read.

Two emails should arrive:

- **to you**, the routine sheet, from `hello@remindly.care`, replying to
  `hello@remindly.care`
- **to the admin address**, "New Remindly subscriber", showing the `source` and
  the running total, replying to the subscriber

**Why this one matters most:** background jobs did not run in production at all
until PR #41. `deliver_later` silently enqueued and nothing ever sent. A mailing
list that quietly delivers nothing looks exactly like one that works.

### 2. Sign in with a magic link

Every mailer now sends from one address. If that address were ever rejected,
**login breaks for everybody** — this is the highest-consequence path in the app
and it depends on the same sender as everything else.

### 3. Print both sheets on actual paper

<https://www.remindly.care/routine_sheet> and
<https://www.remindly.care/caregiver_checklist>.

Measured at 1.00 and 1.01 A4 pages in a headless browser, which is not the same
as a printer. Check: each fits one sheet, the checklist's day boxes are big
enough to tick with a pen, and the routine sheet's writing rows are big enough
to write in — those rows were accidentally shrunk once by print rules meant for
the checklist.

### 4. The voice page actually speaks

Sign in as a senior with at least one reminder due, open `/voice_reminders`,
tap through the audio gate, and listen. Browsers refuse speech until the page
has been touched, and a page that cannot speak looks identical to one with
nothing to say.

## Why these and not others

Every item is a failure this project has had or narrowly avoided:

- Solid Queue not running in production (PR #41)
- `notifications@remindly.app` rejected on every send, fixed in one mailer while
  six others kept the same broken fallback
- an unmonitored `noreply@` as the only advertised unsubscribe route
- public pages recording IPs while the privacy policy said they did not — and
  the specs that should have caught it passing because they sent no User-Agent
- print rules for one sheet shrinking the handwriting rows on another
