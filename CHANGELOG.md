# Changelog

All notable changes to the Remindly project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **A Mandarin call script, written and shipped without becoming speakable.**
  Asked for by the caregiver who reviewed Remindly, whose own community is
  Mandarin- and Cantonese-speaking. Cantonese is still impossible — `yue-HK` is
  absent from Telnyx's speak enum at any price — but `cmn-CN` is in it, so the
  words were the whole job.

  Shipping them was the problem. `ENABLE_TRANSLATED_CALLS` is on in production,
  and it is one switch for every language, so a new file under
  `config/locales` became selectable for real calls the moment it merged. That
  is how the Spanish draft came to be reachable while its own header still said
  no native speaker had read it — and that draft, machine-written and plausible
  and past a round trip through Google Translate, told a care receiver the call
  was being made on her own behalf.

  So the wait is now recorded per language: `User::SPOKEN_LANGUAGES` carries
  `offer:`, and the picker and the endpoint behind it both read it.

  Mandarin itself ships **offered**, which is a decision and not an oversight:
  the reviewer being asked to judge the script is a Mandarin speaker, and the
  way to ask is to let her use it as a caregiver would. The words are still
  unreviewed and the file still says so. The three things such a
  reviewer has to decide — whether a Mandarin voice can say "Remindly" at all,
  the 您/你 register, and what happens to an English reminder title spoken
  verbatim — are written into the file rather than left for them to find.

### Fixed
- **The call-language box named a language the account was not set to.** It was
  built from the languages on offer alone, so an account holding one that had
  been withheld showed the first option instead — "English" for an account set
  to Mandarin — while the line directly beneath it correctly said 中文. Two
  claims about one setting on one screen, and pressing Save wrote the false one,
  silently moving somebody's calls to a language nobody chose.

  A withheld language is now shown as its own option and disabled: visible so
  the screen is true, unpickable so it stays the one thing nobody may choose,
  and leaving it for a language that is offered still works — trapping a
  caregiver on an unreviewed script would be worse than the state the gate
  exists to avoid. Saving without changing anything is no longer refused.

### Changed
- **A reason the missed email cannot explain can no longer be recorded against
  an occurrence.** The email branches on why the telephone stayed quiet, and the
  reasons it knows were a comment — which had already failed at the job. Two
  were added without being written down, and the second of them reached review
  with no branch in the subject line, so the body explained itself while the
  subject still said "No confirmation from Nora": the sentence that says she was
  asked and did not answer. A reason with no branch of its own does not fall
  through to nothing, either. It falls into the generic wording, which is the
  calling-hours sentence, and tells a caregiver the call fell outside the hours
  calls may be placed when it did not — an explanation, and the wrong one.

  The list is now the code's rather than a comment's: an unknown reason is
  refused when it is written, and the mailer spec walks the list and requires
  each reason to produce a sentence no other reason produces. Nothing a
  caregiver receives changes today; what changes is that the next reason cannot
  be added without the email having something of its own to say about it.

### Fixed
- **The missed email told a caregiver nobody had asked, when the screen had
  asked.** Under every phone failure it ended "only that Remindly did not ask",
  which is not true of anybody using Remindly: both channels fire, so the same
  reminder was announced on the care receiver's screen with a Done button beside
  it. The telephone is the only channel this email has evidence about, and it now
  says only that — that Remindly did not reach them by phone.

  The sentence also sat inside each branch of the text mail rather than outside
  all of them, so carrying it was something a person had to remember. Two of the
  four reasons never carried it, and a third shipped without it and had it put
  back by hand. It is written once now, where the HTML mail has always had it.

  The text mail's lines were also long enough to wrap badly in a narrow window —
  87 characters at the worst — which plain text does not reflow its way out of.
  Rewrapped against the longest date the format can produce rather than today's.

- **A reminder edited to a time that had already passed was reported as the care
  receiver's failing.** Editing a reminder re-expands its occurrences and
  back-fills the most recent past slot of the day, so a row could be written at
  8pm for 7pm. Remindly correctly refuses to telephone about a dose whose moment
  went by before the row existed — but the refusal was not recorded, so the
  missed email fell through to the wording written for the web client and told
  the caregiver the person had not marked it done. Nobody had been asked: the
  occurrence existed only after its own due time. The decision is now written
  down, and the email says the reminder was added after its time had passed and
  that no call was placed for it. Not that nobody asked her: the screen client
  announces a back-filled reminder like any other, so whether she was asked is
  not something this email can know. What it knows is that the telephone stayed
  quiet.

- **A reminder call spoke the medication title to voicemail.** Telnyx answers a
  mailbox exactly as it answers a person, so the announcement played into the
  recording and the title went with it — further than the room the privacy
  policy warns about, because a mailbox keeps it, syncs it and hands it to
  whoever holds the phone. Every reminder call now opens with a line carrying no
  title or name, and the reminder itself is spoken only after a keypress. A
  mailbox cannot press a key, so a title can no longer reach one.

  Answering-machine detection was built for this first and abandoned: on live
  calls its verdict came back inverted, calling a silent person a machine and a
  real mailbox a person. Nothing is now asked of the provider and nothing is
  inferred. The cost is one keypress for every care receiver, which buys a
  guarantee that does not depend on a classifier being right.

  The call also pauses briefly before speaking, so it no longer talks over
  somebody who has just said "hello".

- **A keypress arriving a moment late was lost, and the reminder rang back.**
  The announcement runs about eight seconds and the wait for an answer was ten,
  so somebody who pressed while it was still speaking, or a moment after it
  finished, was not heard — the dose stayed unacknowledged and the call came
  again five minutes later. The wait is now twenty-five seconds and the prompt
  is repeated once, which rescues that person within the same call instead of
  ringing them again. Waiting longer costs nothing on a call somebody answers,
  since it ends as soon as a key is pressed.

- **A repeated webhook could mark a dose taken while the reminder was still
  playing.** The keypress that asks to hear the reminder and the keypress that
  acknowledges it arrive as the same event carrying the same digit. Telnyx
  redelivers an event when it does not receive a 2xx — including when the reply
  was sent but never arrived — so a redelivery of the first was read as the
  second. The event that got past the opening line is now recorded, and a repeat
  of it is recognised rather than acted on.

- **The time-critical checkbox said nothing about being inert.** The early alert
  fires only from an unanswered call, so for a care receiver without phone
  reminders — or anywhere the feature is switched off, which is how development
  usually runs — ticking the box changes nothing. The form now says so, and says
  what still happens instead: the missed alert, an hour after the dose was due.
  Letting somebody tick it for a dose that matters and believe they had bought
  fifty minutes is the worst version of this.

- **The largest text size broke the layout it was built for.** On a phone at
  150%, the caregiver dashboard put its buttons on top of the heading, the
  action button on each care receiver's row rendered as "Vie…", and the care
  receiver page's subtitle wrapped into the buttons beside it. Every one of
  those rows was a flex that could not wrap, which is invisible at desktop
  width and unmissable on a phone — where the people who need the largest text
  actually are.

  Seventeen page headers stack now instead of competing for one line, button
  groups wrap, and the caregiver row can shrink. The fix is `flex-col` on narrow
  screens with `sm:flex-row` above, and `min-w-0` where a flex child was
  refusing to shrink below its content and pushing its sibling off the edge.

- **Two amber blocks stacked on the reminder form.** For a care receiver whose
  calls are not in English, the health warning and the language note sat one
  above the other — nine lines of amber between the title field and the notes,
  at which point neither reads as a warning. The language note is information
  rather than a caution, so it is grey now, matching the note under the notes
  box: amber warns, grey informs.

- **The two development quick-login buttons signed you in as the opposite role.**
  They named a role and passed an email address, trusting the seed data to
  agree about what those accounts are. It does not:
  `caregiver@example.com` holds the care receiver role and
  `senior@example.com` holds the caregiver one, and has for a long time. So
  "Quick Login as Caregiver" signed you in as a care receiver and the other
  button did the reverse. They ask for a role now, which makes the label true
  whatever the fixtures say. Development only.

  The second button also still said "Senior" — on the sign-in page, which is
  the first screen anyone sees, and which the terminology sweep missed by
  scoping itself to signed-in screens.

- **Two screens printed the raw permission value.** The care receiver's own
  dashboard has said "You can make changes" since the permission control
  shipped, while the caregiver's dashboard showed a "Manage" badge and the care
  receiver's page read "Permission: Manage" for the same fact.

### Added
- **A reminder can be marked time-critical, and caregivers hear on the first
  unanswered call rather than an hour later.** Asked for by the caregiver who
  reviewed Remindly, describing Parkinson's medication: the window is narrow
  enough that the gap between "did not answer" and "somebody was told" is the
  thing that matters.

  That gap was fifty minutes. Calls give up after three attempts five minutes
  apart, and the missed sweep waits a full hour after the due time before
  telling anybody; nothing filled the middle. A critical reminder now alerts
  every linked caregiver about a minute after a call goes unanswered — normally
  the first, though the alert fires on any of the three so a lost webhook does
  not mean silence.

  It says nobody has answered *yet*, not that the dose was missed — two more
  calls are still coming, and a caregiver acting on it may still catch the dose
  in time. It is a distinct notification type for the same reason: sharing one
  with the missed alert would let the uniqueness index swallow the message that
  means the dose really did not happen.

  Every linked caregiver hears, not only those who opted into the reminder's
  category. That preference exists so nobody is woken by hydration reminders,
  and a dose marked time-critical is the case it was never meant to filter out.
  Quiet hours are ignored deliberately: 3am is when this matters most.

  The calls themselves are unchanged — still three, still five minutes apart.
  What changed is when the people who can do something about it find out.

  A caregiver whose address has already hard-bounced gets the in-app alert and
  no mail job, matching the completed and missed paths. The in-app alert is
  unconditional in the same way: it is written before the mail is enqueued, so
  a broken queue costs the email and not the alert.

### Removed
- **Switching your own role from the profile.** It offered a one-click move to
  whichever role you were not, and the two dashboards are not variations of each
  other: a caregiver sees the people they care for, a care receiver sees their
  own reminders. Pressing it swapped the whole screen, and the only way back was
  to press it again. Nothing recorded that it had happened — no audit entry, no
  email, no analytics — so there is no evidence anyone ever used it, in either
  direction.

  Choosing a role still works, which is the part that matters: a new user
  arrives without one and picks at sign-up, rather than waiting on an admin.
  What is gone is changing a role already chosen. `User#choose_role_once`
  refuses it rather than the button merely being hidden, because a removed
  control with a live endpoint behind it is not a removal.

  Anyone who genuinely picked wrong now asks an admin, who has a screen for it
  that emails the user about the change — more of a record than the self-serve
  path ever left. The profile states the role and says where to write.

  The problem underneath is untouched and worth naming: roles are exclusive, so
  a daughter managing her mother's reminders cannot also have her own. Switching
  was never a fix for that, only a way to trade one for the other.

- **The `/api` namespace, which had never run.** All three controllers under it
  opened with `before_action :authenticate_user!` — a method defined nowhere,
  since `ApplicationController` defines `authenticate!` — so every action raised
  `NoMethodError` before reaching any code. `/api/tasks`,
  `/api/tasks/:task_id/comments` and `/api/availability` would have answered any
  request with a 500 from the day they were added in October 2025 — though none
  ever arrived, which is the next paragraph and the reason nobody noticed.

  Nothing called them: no JavaScript, no Swift, no fixture, and production
  logged no request to any of them. Nothing tested them either, which is how a
  typo fatal to every request in a namespace went ten months unnoticed.

  They date from the client-server era, before the standalone voice client was
  retired in favour of `/voice_reminders` inside the Rails UI. That retirement
  gave the reason to delete rather than repair: it recorded a day of voice fixes
  landing in the copy nobody used and needing to be ported afterwards. A dead
  endpoint that looks live is where somebody reasonably adds their next task
  endpoint, and finds it does nothing.

### Added
- **A care receiver decides whether a caregiver may change things, or only
  look.** Removing somebody entirely was already offered on their own dashboard;
  limiting what one can do — the smaller version of the same decision — was not,
  so the only way to hold a view caregiver was a console. The choice now sits
  beside Remove Access, where the larger one always has.

  With the care receiver rather than an admin, for the same reason as everything
  else here: only they can agree to phone calls, only they can generate a
  pairing token, and a family sorting out who does what should not have to email
  the developer. A caregiver cannot promote themselves or demote a colleague —
  the action is scoped to the links where the current user is the person being
  cared for.

  Dropping somebody to view leaves phone reminders already agreed alone. The
  calls were consented to by the care receiver, and ending them because their
  helper's permission changed would punish the wrong person.

### Fixed
- **"View" now means view.** A caregiver holding the view permission could
  create, edit and delete tasks, reminders and unavailability exactly like
  anybody else: three checks guarded the phone panel and nothing guarded the
  rest, so a permission whose name promised a restriction applied none. Writes
  are now checked through `User#manages?`, and the forms are refused rather than
  merely hidden — a gated button with an open endpoint behind it is the shape
  every permission bug in this codebase has taken so far.

  Nobody holds view today; every caregiver link is manage since pairing was
  fixed. So this guards a role that does not exist yet, which is the point. The
  alternative is leaving a name to be trusted by whoever adds one.

  Inviting counts as a write, and is the sharpest of them: an invitation creates
  a *manage* link, so a view-only caregiver could otherwise invite an address
  they control, sign in as it, and hold everything the restriction had just
  removed — bypassing every other check through the endpoint that hands out the
  permission being enforced. Connected-calendar sync is guarded too, since it
  writes tasks; that feature is switched off, but a flag decides whether a door
  exists rather than who may walk through it.

  Checked in two places, doing two jobs. The controllers refuse regardless —
  that is the boundary, and a hidden button has never been one. The pages also
  stop offering New Task, Create Reminder, Invite Caregiver, New Time Block and
  the per-row edit and delete controls to somebody who cannot use them, so a
  view-only caregiver reads a page they can act on rather than one that argues
  with them.

  A care receiver is unaffected: they hold no permission at all, because the
  column describes what a *caregiver* may do and the data is theirs.

- **No caregiver could reach the phone panel, because nothing ever granted
  `manage`.** The permission column defaults to view, `pair_with` never touched
  it, and no screen — not even the admin panel — could change it. So every
  caregiver who paired the documented way was permanently unable to save a phone
  number, place the verification call, or choose the language calls are spoken
  in. That is the feature the product leads with, enabled in production, behind
  a permission the application never issued. It went unnoticed because every
  link in development had been set to manage by hand; walking a brand-new
  caregiver and care receiver through pairing from scratch is what surfaced it.

  Both paths that create a link now grant manage, and a migration gives it to
  the caregivers already linked. Unclaimed pairing tokens are left alone — a row
  with no caregiver is a token waiting to be claimed, not somebody holding the
  wrong permission.

  Worth being precise about what this grants: the ability to *ask*, not to
  enable. `callable_by_phone?` still requires a number, a recorded consent and
  no opt-out, and only a keypress on a call the care receiver answers writes
  that consent. A caregiver can now arrange calls; they still cannot agree to
  them on somebody else's behalf.

- **A care receiver with nobody linked was told to pair with a care receiver.**
  The empty dashboard served both roles but only ever offered the caregiver's
  action, so somebody waiting to be looked after was sent to a form asking for a
  pairing token that only a caregiver would have been handed — while the thing
  they actually needed, generating a token of their own to share, sat behind a
  button the empty state did not mention. It read "Pair with Senior" before the
  terminology change, wrong in the same way and easier to miss. Each role is now
  asked for its own half of pairing, and asked once: the header repeated the
  empty state's button, which had gone unnoticed only because the two said
  different words.

### Changed
- **Remindly says "care receiver" where it used to say "senior".** A caregiver
  reviewing Remindly asked for a word that does not assume age: not everyone
  being cared for is old, and the old one quietly narrowed the product to a
  subset of the people it serves. Every screen behind sign-in now uses it —
  dashboards, task and pairing forms, role labels, admin, and the role-change
  email — along with the prose on the public pages, the terms and the privacy
  policy.

  The stored value is untouched. `senior` remains the role enum value, four
  foreign keys and most of this suite; the change is a `User#role_label` and the
  copy around it. Renaming the column would migrate data to change a word
  nobody stores for its own sake, touch every file shipped this week, and show a
  user nothing.

  Page titles, meta descriptions and og tags keep "seniors", as does the
  reminder-app-for-elderly-parents landing page. Those are search terms — people
  type "reminders for elderly parents", not "care receiver app" — and renaming
  them to broaden appeal would have narrowed discovery instead. Meet people
  where they search, then do not exclude them once they arrive.

### Added
- **Reminder calls can be spoken in Spanish.** A caregiver reviewing Remindly
  asked for calls in a language other than English, and the people the calls
  exist for — those who do not use a screen — are the least likely to be served
  by an English-only line. The senior's page now carries a language for their
  calls, set by the caregiver because the senior is often the one who never
  signs in, which is the same fact that makes the calls worth having. Only the
  telephone changes; the dashboard stays English throughout.

  Both spoken prompts are translated, not just one. Translating the reminder
  and leaving the consent call in English would mean the first thing a Spanish
  speaker ever hears from Remindly is English asking them to press a key — the
  call whose entire job is to not sound like a scam.

  The Spanish is machine-written and marked as such in
  `backend/config/locales/voice.es.yml`; it must be read by a native speaker
  before it is relied on, and sits behind its own `translated_calls` flag so
  that is a decision somebody makes rather than a side effect of merging. The
  flag is on in production, because the only way to validate a call script is
  to hear one — a native speaker is taking a real call, and reading the file
  would not catch register or pace, which is where the risk actually lives. The
  constraints the English is written against are recorded in
  `backend/config/locales/voice.en.yml` as translator notes, because
  they are requirements rather than style: Remindly named in the first breath,
  the arranger named early, no suggestion that the called party asked for
  anything, and the keypad digits left alone.

  Remindly translates its own words, not the caregiver's. A reminder title is
  free text and reaches the voice exactly as typed, so a senior set to Spanish
  would otherwise hear "Take meds" dropped into the middle of a Spanish
  sentence — and the caregiver who chose the language had no way to know that
  from the screen. Both the language control and the reminder form now say so,
  naming the language that is actually set. Translating titles automatically
  was considered and rejected: it would send every title to a third-party
  translator — the same titles the forms ask people to keep clinical detail out
  of — from inside the webhook that has to answer before the call can speak,
  and a wrong translation of "take 2 of the white ones, not the blue" would be
  read aloud with total confidence to somebody who cannot check it.

  Cantonese was asked for and is not possible — it is absent from Telnyx's
  speak enum at any price. Every other language on that list is now a YAML file
  and one entry in `User::SPOKEN_LANGUAGES`, with no new code.

- **Caregivers are asked to keep health details out of titles and notes.**
  The privacy policy has always covered this, but nobody reads a policy while
  filling in a form, and a caregiver reviewing Remindly asked for the prompt to
  be where the typing happens. An amber notice now sits under the
  title field on the new reminder, edit reminder, and task forms. It gives
  reasons somebody can act on rather than citing regulation: the reminder title
  is spoken aloud by the call, in whatever room the phone is in, and every
  linked caregiver reads it on their dashboard. The task form says only the
  second, because task titles never enter the call flow and claiming otherwise
  would teach people something false about their own data. The notes and
  description boxes carry a quieter one-line version rather than a second amber
  panel: they cannot go uncovered, since a field labelled "Additional details"
  is where a dosage actually ends up and the policy asks for titles *and*
  notes, but two panels on one form would be read as decoration. Deliberately
  not a validation — no rule catches "Take lorazepam" without also catching "Take
  pills with breakfast", and a form that argues with people gets abandoned
  rather than obeyed.

- **Text size is a setting now, because the app was too small for the people it
  is for.** A caregiver reviewing Remindly said the type was too small for the
  seniors she works with, which is a hard thing to answer with a browser zoom
  the person has to rediscover on every device. Profile now offers Normal,
  Large, Larger and Largest, stored on the user so it follows them from the
  tablet to whichever phone they are handed. It moves the root font size rather
  than a list of text classes: Tailwind sizes padding and tap targets in rem
  alongside type, so one number grows the buttons with the words, and bigger
  labels wedged into the same cramped controls would have helped nobody.
  Breakpoints are in px and stay where they are, so the responsive layout is
  untouched.

### Changed
- **The privacy policy no longer contradicts the app.** It described reminder
  titles and notes as things that "may name a medication or an appointment",
  which was accurate until the forms started asking people not to do that. It
  now carries a section on health information saying what we ask for and why.
  It stops short of claiming Remindly holds no health data: titles are free
  text, whatever is typed is stored, and nothing is scanned or blocked. A
  policy promising otherwise would be the more expensive kind of wrong — the
  live exposure for a health app outside HIPAA is the FTC Health Breach
  Notification Rule and state laws like Washington's My Health My Data Act,
  and both turn on whether the policy is accurate rather than on whether
  health data is held.

- **Scheduling integrations are hidden, because they were never finished.** The
  `external_scheduling` flag was declared alongside the feature and then never
  checked anywhere, so the screens have been reachable since the day they were
  written. Nothing syncs on a schedule — there is no job in `recurring.yml` —
  so an integration only pulls appointments when somebody presses Sync by hand,
  which is not what "connect your calendar" offers. Production has never held
  an integration or a synced task. The flag now defaults off and is checked in
  the controller as well as on the nav button, because a hidden link is not a
  closed door and those routes stay live for anyone holding a URL. Kept as a
  flag rather than deleted: the model, controller and Acuity client work as far
  as they go, and what is missing is the periodic sync that would make them
  mean anything.

- **The daily call cap is a backstop again, not a rationing mechanism.** Ten
  calls per senior per day meant three unanswered reminders exhausted it, and on
  the first day of live calls the evening dose got one ring instead of three
  because the morning had spent the budget. It is twenty now, which covers six
  reminders exhausting their retries. Still a constant a caregiver cannot edit,
  because a per-senior daily ceiling is invariant 7 — raising it does not weaken
  that, it stops the ceiling deciding which reminder matters least.

### Fixed
- **The task backfill skipped two of the five rows it existed to fix.** Its
  scope excluded recurring templates with `rrule: nil`, which is `IS NULL` in
  SQL — but the task form submits an *empty string* for a one-off task rather
  than leaving the column NULL. So two ordinary appointments read as outside
  the scope and kept the wrong time, including the cardiologist appointment
  that prompted the original fix. `Task#recurring_template?` has always used
  `present?`, so the application had this right and only the migration did not:
  blank and NULL are the same answer to "is this recurring". A second migration
  shifts exactly the rows the first missed, and cannot touch the ones it already
  corrected. It is also bounded to rows untouched since the parser fix went
  live: that fix shipped in the same deploy as the first migration, so anything
  created or resaved afterwards already stores a correct instant and carries a
  blank rrule too — production grew exactly such a row within minutes. Caught by
  checking production after deploying rather than assuming the count meant the
  right rows moved.

- **Opening a moved senior's task and saving it untouched shifted the
  appointment.** The task form pre-filled from `Task#zone`, which prefers the
  task's own `tz`, while its hidden field submitted `@senior.tz`. Those agree
  until a senior changes timezone, and then the same unedited text was parsed
  back in a different zone — a cardiologist appointment jumping two hours for
  someone who had moved from New York to Denver, from a save that changed
  nothing. The form now names one clock in all three places: the pre-fill, the
  label beneath it, and the `tz` it submits. Whether a task's `tz` should follow
  a senior at all is a separate question, left open as #105; this only
  guarantees a single form agrees with itself.

- **A task typed as 3pm was stored as 3pm UTC, so the senior saw 11am.** The
  task form submits wall-clock text with no zone in it, and `Time.zone` is UTC
  app-wide, so Rails cast a caregiver's "3:00 PM" to `15:00 UTC` — four hours
  off for a senior in New York. The caregiver's own task list still read 3:00 PM
  because it rendered the raw instant back without converting, so one bug
  cancelled the other and nothing looked broken until the two screens were put
  side by side. Found on a real cardiologist appointment while preparing a demo.
  Times are now read in the clock of the person the task is for, `Task#zone` and
  `#scheduled_at_local` are the single place that knows which clock that is, and
  the edit form pre-fills in it — previously opening a task and saving it walked
  the appointment another four hours, silently, every time. Existing rows are
  repaired by a migration that only shifts and is reversible, scoped to rows the
  web form could have produced: synced appointments, recurring children and
  templates all store correct absolute instants already, and shifting them would
  break data that was never wrong.

- **The missed-reminder subject ended on the word "done".** *"Mom hasn't marked
  Metformin as done"* is correct and reads badly where a subject is actually
  met: in a notification list the eye takes the tail, and the tail was
  "Metformin as done", with the negation four words back in a sentence nobody
  finishes. It now leads with the signal — *"No confirmation from Mom:
  Metformin"* — so the sentence denies confirmation before the title is reached.
  The title still comes last and is whatever the caregiver typed, so "Check the
  laundry is done" ends on that word regardless; what the specs pin is the
  opening, and that the old "… as done" construction cannot come back.
- **Occurrences were only materialised when somebody opened a page.**
  `Recurrence.expand` was called from five places, all controllers — and the only
  one that ran repeatedly was the senior's own dashboard index. A caregiver
  viewing their senior's page did not expand; the voice page did not; nothing on
  a schedule did. That was coherent while Remindly was something you looked at,
  because the visit that created an occurrence was the visit that displayed it.
  Reminder calls invert it: delivery happens with nobody looking, for a senior
  who may not use a screen and, by design, may have no login at all. Their
  occurrences quietly stopped being created a day after setup, so nothing rang
  and nothing was reported missed either. `ExpandRemindersJob`
  now runs hourly — ahead of the times it creates, since a row written after its
  own hour is correctly refused a call.
- **Expanding a reminder no longer replays its whole history.** `Recurrence`
  enumerated every occurrence from the reminder's original `start_time`, to keep
  the two it acts on: 245 timestamps for an eight-month-old daily reminder,
  growing by one a day, and roughly 8,760 a year for an hourly one. Harmless
  while this ran on a page visit, multiplied by twenty-four by the hourly sweep.
  It now asks only for the window it can act on, which produces the same
  occurrences. Recurring tasks had the identical waste and are bounded the same
  way.
- **A second verification call could still reach a senior who had just agreed.**
  `verify_phone` checked consent before reserving, so a request that began while
  the first call was still ringing read "not yet consented", and if that call
  then landed its keypress — recording consent and freeing the in-flight claim —
  the reservation succeeded and dialled somebody who had agreed a moment
  earlier, offering them a 9 to switch off what they had just turned on.
  Consent is re-read after the claim now, on the pattern `VoiceReminderJob`
  already used.
- **Reminder titles no longer appear in deploy logs.** The timezone repair
  migration named each affected reminder in its output, and a title is often a
  medication name — read by anyone with access to CI or deploy logs, long after
  the deploy. Identifiers only.
- **The caregiver screen kept offering to ask a senior who had already agreed.**
  The *Call and ask* button rendered whenever a number was saved, including once
  consent was recorded — so pressing it rang the senior to ask a settled
  question, and the script it plays ends "press 9 and we won't call again". Its
  best outcome was a no-op and its worst was a senior switching off reminders
  that were working. It now appears only while there is something to ask, and
  `verify_phone` refuses such a request outright — a screen is not a guard, and a
  tab opened before another caregiver finished verifying still holds a live
  button. Both still allow it after an opt-out, since that keypress is the only
  thing that can lift one.
- **Reminders drifted by an hour whenever the clocks changed.**
  `RemindersController` permits `tz` in its params, so the JSON API stamped a
  reminder with whatever zone the calling device sent — a caregiver whose own
  device said New Delhi created New York seniors' reminders stamped "New Delhi".
  Recurrence expands the schedule in that column, and New Delhi has never
  observed daylight saving, so the senior's clock moved twice a year and the
  reminder stayed where it was. Two on the production account had drifted an
  hour, and one had drifted past 9pm, out of the calling window, where it would
  silently have stopped ringing at all. A reminder is now always kept in the
  clock of the person it is for, whatever a caller supplies, and saving one
  repairs it. A migration normalises the zone spellings and reports any reminder
  still stamped with somebody else's clock, without touching it: repairing one
  safely means reconciling occurrences that already exist at the old times, which
  is a tool somebody runs and reads, not an unattended deploy step.

### Changed
- **Caregiver screens name the senior instead of showing their email address.**
  A caregiver looking after three parents read a column of mailboxes and had to
  translate each one back into a person. `User#display_name` already resolved
  this and the senior list already used it; the senior's page, both reminder
  forms, the invite page and the task form now do too. The senior's page no
  longer shows the address as detail beside the timezone: disambiguation belongs
  in the list where a caregiver chooses between people, which already shows it,
  and a caregiver-created senior may have no meaningful address at all. It can
  still appear as the heading itself, since `display_name` falls back to it for
  a senior with no name yet — better than a blank heading.

### Fixed
- **Editing a reminder could telephone the senior about a dose whose time had
  already passed.** `Recurrence.expand` deliberately back-fills the most recent
  past slot of the day, so editing a reminder writes a pending occurrence dated
  earlier today — which keeps a same-day reminder visible on the dashboard and
  is the right behaviour there. The call scheduler could not tell that row from
  one that had just come due, so editing a reminder at 8pm to ring at 7pm would
  have rung the senior immediately. Neither the scheduler nor the delivery job
  will now call about an occurrence written after the time it names.
- **The phone-calls kill switch did not cover the button that places a call.**
  `ENABLE_PHONE_CALL_REMINDERS` gated the scheduler and the delivery job, so
  scheduled calls were off — but a caregiver pressing "Call and ask" reached
  Telnyx regardless, and the panel offering it rendered unconditionally.
  Shipping the feature switched off would still have let anyone with manage
  permission telephone a real senior. Both endpoints now refuse while the flag
  is off, and the panel is hidden with them.
- **A verification call could be placed after 9pm, or leave a reservation that
  never rang.** `verify_phone` reserved the attempt and then asked about calling
  hours on a second reading of the clock, so a request straddling 21:00:00 could
  pass the model's guard at 20:59:59.9, create the row, and be refused at
  21:00:00.1 — dialling nothing while leaving a reservation that held the
  senior's line and spent one of the five daily attempts. The clock is now read
  once for the decision. It is then read once more immediately before the
  provider call, because consistency is not currency: reserving on a stale
  reading and dialling after the boundary would have placed a real call outside
  the legally enforced window. If the window does shut in between, the
  reservation is undone rather than banked: nothing was sent to the provider, so
  it costs the caregiver none of their five daily attempts.
- **A finished call kept blocking the senior's next one.** `completed_at` was
  only written when the hangup event found the outcome still `pending`, so a
  call where nobody pressed anything — the outcome having already been set to
  `no_response` by the gather — never recorded that it had ended. Harmless until
  the one-call-at-a-time guard started reading that column to decide whether a
  senior may be called again, at which point a call that finished twenty seconds
  ago went on occupying the line for five minutes. Completion is now recorded
  unconditionally; only the outcome stays conditional, so a hangup arriving
  after a keypress cannot overwrite what the senior said.

- **A senior could be telephoned twice at the same instant.** Found in a live
  test: a dose falling due at the same moment as another occurrence's retry
  placed two calls in the same second to the same phone. One was answered; the
  other talked to voicemail, having spent a daily slot on a call that could not
  possibly be picked up. Nothing prevented it — `MAX_CALLS_PER_DAY` bounds the
  day and `MAX_ATTEMPTS` bounds the occurrence, and neither bounds concurrency.
  A reservation is now refused while that senior has a call in progress; the
  skipped occurrence stays pending and the scheduler, which runs every minute,
  offers it again once the line is free. An attempt that never rang does not
  occupy the line, and one abandoned by a dead worker stops counting after five
  minutes rather than blocking the rest of the day.

- **A missed call left two identical messages on the voicemail.** Found in a
  live test, not by a reviewer: Telnyx re-speaks a `gather_using_speak` prompt
  when no digit is collected, and `maximum_tries` was never set, so it used its
  default. One `call.answered` event, one gather command from us, and two
  recordings sixty-one seconds apart against a ten-second timeout. It is now
  explicitly `1` — a repeat only helps someone who fumbled the first prompt, and
  costs another voicemail message every time nobody picks up, which is exactly
  what makes an automated caller feel like a robocall. The real answer is
  answering-machine detection, which the design document already requires
  ("voicemail is not delivery") and which is not built: a machine answering is
  currently recorded as an answered call that happened to collect no digit.

- **Reminder calls had no upper age limit.** The scheduler matched every
  pending occurrence ever scheduled, and occurrences do not age out on their
  own: `MarkMissedOccurrencesJob` sweeps only within its seven-day
  `MARK_LOOKBACK`, so anything unacknowledged for longer stays `pending` for
  good. One production account had accumulated thirty such rows over six months,
  the oldest from the previous November — switching the feature on would have
  telephoned about ten of them within a minute of each other, then ten more
  every day, indefinitely. `LOOKBACK` bounds it to two hours: enough to survive
  a queue backlog, short enough that nobody is rung at bedtime about a dose due
  at breakfast. A call is far more intrusive than the status write the missed
  sweep performs, so its window is deliberately much tighter.

- **The daily cap still was not a cap, and four more.** The slot number came
  from a moving `maximum` while the cap came from a separate `count`, which two
  workers defeat: both pass the count at nine, the first takes slot ten, the
  second then reads a maximum of ten and takes eleven. Nothing collides. There
  are now exactly `MAX_CALLS_PER_DAY` slots in a day and a reservation claims
  the lowest free one, so two racing reserves pick the same slot and the index
  refuses one; a slot is released when an attempt turns out never to have rung,
  so it can be reused rather than leaving a hole. A senior's timezone is
  editable and the day hangs off it, so changing zones handed back a fresh set
  of slots — the zone each attempt was filed under is now recorded, which
  catches that without refusing the ordinary morning call after a full evening.
  A `reserved` row whose worker died was reported to caregivers as "we tried to
  call and could not get through", when nothing had reached the provider. And
  cancelling an attempt while recording why were two separate writes, so a
  crash between them left a state nothing could repair.
- **The Ed25519 webhook signature path had no test at all.** It is the
  production verification mode for a public endpoint that writes
  acknowledgements, and every spec stubbed the public key to nil, so it never
  ran. A regression in the header names, the signed-message format or the base64
  decoding would have passed CI and surfaced only once signature mode was
  switched on — at which point every callback would be rejected and no reminder
  call could be acknowledged.

- **A fifth review round: seven more, one of them user-visible.** The missed
  email's subject handled two of the three no-call reasons, so
  `not_attempted_in_time` fell through to "hasn't marked it as done" while the
  body of the same message said "Remindly did not call" — the subject blaming
  the senior for a call that was never placed, which is the exact failure that
  reason exists to prevent. The per-senior daily cap was a count followed by an
  insert, which three Solid Queue worker threads can all pass at once; it is now
  a `(user_id, call_day, daily_sequence)` unique index, so two reserves
  computing the same slot cannot both win. That cap also counted attempts where
  the phone never rang, so ten failures early in the day silenced every later
  reminder even after the provider recovered. A `cancelled` attempt was
  classified as "we tried and could not get through". `suppress_call!` decided
  first-refusal with a read rather than a conditional update, so two callers
  could each write a different reason. The cancel branch recorded nothing, so a
  sweep that closed an occurrence mid-claim produced a caregiver email claiming
  a call was attempted. And the notifications migration built a unique index
  without collapsing duplicates first — harmless on today's data, but the
  entrypoint runs `db:prepare` at container start, so a raise there aborts the
  boot rather than surfacing in a test.

- **Four more, from a fourth review pass.** The dialling job trusted the
  scheduler's `WHERE` clause for the per-user opt-in, so a senior who switched
  voice reminders off — or a job invoked directly for someone who never opted in
  — was still called; the opt-in is now re-read at dial time, like the status
  and the calling hours already were. `MAX_ATTEMPTS` is per occurrence, so a
  senior with six reminders due could take eighteen calls without exceeding it;
  `MAX_CALLS_PER_DAY` bounds the person rather than the reminder, counted in
  their own day. Correlating a stray callback matched the most recent
  uncorrelated attempt, so a delayed callback from attempt 1 could attach to
  attempt 2 and silence its real call — `client_state` now carries the attempt
  number and the claim is a conditional update on that exact row. And a job held
  in the queue past the missed sweep's grace left no record at all, so the
  caregiver was told the senior ignored a call that was still waiting to be
  placed.

- **Four more ways a caregiver could be told the wrong thing.** An accepted call
  whose `call_control_id` failed to persist could never be correlated, so every
  callback asked for a retry until the provider gave up and the senior stayed
  connected to a call that never spoke — the event's `client_state` now names
  the occurrence, so the reserved attempt is adopted and the call proceeds. The
  scheduler skipped out-of-hours occurrences before `VoiceReminderJob` ever ran,
  so the suppression recording added for exactly this case never executed in
  production, where the scheduler is the only caller. `phone_failure_reason`
  consulted the senior's *current* preferences before the durable record, so
  switching voice reminders off after a failure retroactively turned a call
  nobody placed into a reminder she had ignored. And duplicate notification
  deliveries could race: the "already notified" check was a SELECT against an
  unindexable json column, so both workers passed it — `notifications` now has a
  real `occurrence_id` column with a partial unique index, and the insert
  decides rather than the check.

- **The caregiver email stated the wrong calling window.** `CALLING_HOURS` is
  the exclusive range `(8...21)`, and Ruby's `Range#last` returns the range's
  *end* regardless of exclusivity — so `last + 1 - 12` gave `10` and the mail
  read "between 8am and 10pm" while `within_calling_hours?` actually stops at
  9pm. `.max` respects exclusivity. The suppression log had the same fault,
  reading "8:00-22:00".
- **Four ways an event could be retired without being handled.** A gather that
  failed left the senior connected to silence with no retry, because
  `answered_at` was recorded first and suppressed redelivery; the gather now
  precedes the flag, and Telnyx's `command_id` makes a duplicate harmless. A
  callback arriving before `dial` wrote `call_control_id` back was answered
  `200` and lost for good; `client_state` now identifies our own calls so they
  can be retried, while genuinely foreign ids are still dropped rather than
  retried forever. The caregiver notification was conditioned on a value
  computed inside an already-committed transaction, so a failed enqueue could
  never be recovered by a redelivery; it is now enqueued on every delivery,
  which both the job and the delivery beneath it already tolerate. And a dose
  resolved from another client between the status check and the dial was still
  telephoned about — the status is re-read after the attempt is claimed.

- **An unanswered senior could be telephoned dozens of times.** The scheduler
  skipped occurrences called within the last two minutes, but every dial reused
  one `TelnyxCall` row per occurrence, so its `created_at` never moved past the
  first attempt and the window stopped excluding anything. Running every minute
  against an occurrence that stays `pending` for the full 60-minute miss grace,
  that is around fifty consecutive calls to someone who did not pick up — all
  inside legal hours, so the calling-hours guard could not help. Attempts are
  now one row each, capped at three and spaced five minutes apart, per the
  design document's "retries after a few minutes, twice at most, then stops".
- **Two runs could both dial the same dose.** Nothing was written before the
  provider was called, so a redelivered job or two overlapping scheduler runs
  each POSTed without being able to see the other. An attempt is now claimed
  first, and a unique index on `(occurrence_id, attempt_number)` decides the
  race in the database — the loser is told before it dials rather than after.
- **A failed keypress was reported to Telnyx as success.** The handlers rescued
  every error, logged it, and still answered `200`, so the provider considered
  the event delivered and never resent it. A transient write failure therefore
  discarded the senior's "1" for good: the occurrence stayed pending and the
  caregiver was later emailed that she had not marked it done. Failures now
  propagate and the endpoint answers `500` so Telnyx retries; every handler is
  idempotent, and there are specs for the redelivered case.

- **A call that could not be placed also said the senior hadn't marked it
  done.** The previous fix covered calls suppressed for calling hours, but not
  calls that were attempted and never reached the provider — a missing API key,
  the provider down. Those left the occurrence pending, the sweep marked it
  missed, and the caregiver was told their mother had not marked her dose done.
  This is the state production is in today, with no `telnyx:` credentials at
  all: enabling voice reminders there would have produced that email for every
  single reminder. `Occurrence#phone_failure_reason` now separates the two
  cases, and the mail says which — "Remindly tried to call Mom about Metformin
  and couldn't get through", with the attempt count and an admission that the
  fault is ours. An attempt only counts as a real call once it has a
  `call_control_id`, which is the provider's receipt; testing the attempt row's
  mere existence let a reservation that failed before the API call masquerade
  as a call that rang.
- **A reminder that was never called said the senior hadn't marked it done**:
  once calls are confined to 8am–9pm, a 6am dose for a senior whose only channel
  is the telephone is suppressed at 6:00, marked `missed` at 7:00 by the sweep,
  and emailed to the caregiver as "hasn't marked Metformin as done". Nobody was
  asked. Reporting a non-event as a lapse sends a caregiver looking for a
  failure that never happened, which is the opposite of what this mail exists
  for. That case now says "Remindly couldn't call Mom about Metformin", names
  the hour and the window, and states plainly that nothing was contacted so it
  implies nothing about what the senior did. It reverts to the ordinary wording
  the moment a call actually went out — a queue backlog delivering a 7:55 dose
  at 8:05 is a real attempt and an ordinary miss.

- **Telnyx webhooks failed open when no token was configured**: a blank
  `webhook_token` meant "accept anything", which reads as a lenient default and
  is actually an open door — production has no `telnyx:` credentials, so on
  deploy `/telnyx/webhooks` would have accepted any POST and let it acknowledge
  a reminder. An unconfigured integration now rejects callbacks instead of
  trusting them, and the token comparison is constant-time.
- **The `base_url` credential still pointed at the legacy domain**: it said
  `remindly.anakhsoft.com`, and two places in the codebase had already been
  written to route around it — the production mailer host is hardcoded because
  the credential "was stale and kept sending caregivers to the old domain", and
  `MagicMailer` prefers the origin the login actually began on. It is now
  `www.remindly.care`, matching `ApplicationHelper::CANONICAL_HOST`, so email
  links, canonical tags and Telnyx callbacks finally agree on one host. The
  mailer host stays hardcoded regardless: login links are the
  highest-consequence path in the app.

### Added
- **Consent to be telephoned, and the only thing that can grant it.** Phone
  reminders shipped inert because nothing in the app could set a number or opt
  anyone in — deliberately, since the obvious screen (a number field and a
  checkbox) would let one person arrange automated calls to another who had
  never agreed. A caregiver can now propose a number and ask its owner a
  question; that is the entire surface. `TelnyxWebhooksController#consent!` is
  the only thing that can *enable* calls — nothing else sets
  `call_reminders_enabled` to true — and its single input is a `1` pressed
  during a verification call. Several paths clear it: an opt-out, and a change
  of number. Pressing `9` stops calls
  immediately and permanently; pressing nothing is declined, which is neither
  consent nor an opt-out, because someone who said nothing has not said stop.
  Changing the number forgets what the old one agreed to. An opt-out survives a
  number change, so a caregiver cannot undo a senior's "stop" by editing a
  field. Verification calls are bounded separately at five per number per day,
  since they are excluded from the daily cap that otherwise limits how often a
  number can be rung.

- **Phone reminders are behind a feature flag, off by default.** Until now the
  only thing preventing calls in production was that no senior had
  `voice_reminders_enabled` and a phone number — two ordinary columns, which a
  single console command sets, and setting them is the only way to try the
  feature there. Calls would then begin within the minute, and stopping them
  would need a deploy. `FeatureFlag.enabled?(:phone_call_reminders)`
  (`ENABLE_PHONE_CALL_REMINDERS`, default false) is the outer of two locks: it
  says the code may run at all, while the senior's own columns say whether it
  runs for them. It is checked in `VoiceReminderSchedulerJob` so no work is
  enqueued, and again in `VoiceReminderJob` because that job is reachable from
  a console or a retry — a flag that only guards the gate is not a kill switch.

- **Reminder calls are confined to 8am–9pm in the called party's own
  timezone**: automated voice calls are regulated and the window belongs to the
  person answering, not the server. `User#within_calling_hours?` is checked in
  two places on purpose — the scheduler, so an occurrence due at 2am enqueues
  nothing rather than a job every minute until the missed sweep claims it, and
  `VoiceReminderJob` itself, because that job is reachable from a console or
  from a retry hours after the failure that caused it, and a call placed at 3am
  cannot be taken back. A timezone that cannot be resolved blocks the call
  instead of assuming daytime. It cannot catch a timezone that is wrong but
  valid — the UTC-12 profile bug resolved perfectly well — which is why
  verifying the number with a real person still matters.
- **Reminders delivered as a phone call, acknowledged from the keypad**: every
  client until now assumed the senior has a screen, is signed in, and will look
  at it. A phone call assumes none of that — it reaches someone whose only
  device is a landline, and it reaches them whether or not they remember an app
  exists. At the scheduled time Telnyx dials the senior, speaks the reminder and
  collects one digit: 1 marks it done, 2 schedules it again ten minutes later.
  Those are the same two actions `/voice_reminders` offers, and both now run
  through `Occurrence#snooze!`, so a keypress and a tap cannot drift apart — a
  snooze resolves the occurrence *and* schedules the next one, which recording
  the acknowledgement alone would not. An unanswered call records `no_response`
  and leaves the occurrence pending, deliberately not "skip": nobody chose
  anything, so the missed sweep still claims it and the caregiver is still told.

  **Not yet fit to enable in production.** There is no consent record, no
  verification that a number reaches the person it is meant to, and no
  answering-machine detection — and no way for anyone to opt in, since nothing
  in the app sets `voice_reminders_enabled` or `phone`.
  `docs/PHONE_CALL_REMINDERS_DESIGN.md` sets out what has to exist first, and
  why the timezone fix from August is load-bearing here: a user silently moved
  to UTC-12 would be telephoned in the middle of the night. Calling hours *are*
  enforced — see the entry above — and the whole feature sits behind
  `ENABLE_PHONE_CALL_REMINDERS`, off by default, so the scheduled job returns
  immediately and nothing can be dialled.

  Each call carries its own `webhook_url`, resolved from `base_url` or
  `APP_URL`, which overrides the one configured on the Telnyx connection. A
  single URL in the provider's portal has to be hand-flipped between production
  and a tunnel to test anything, and forgetting has no error: the call
  connects, nothing is listening, and the senior hears silence until it times
  out. A base that resolves to loopback sends no override at all rather than a
  URL Telnyx provably cannot reach.

- **A landing page at `/reminder-app-for-elderly-parents`**: the homepage opens
  on the feeling — "caring for a parent from a distance" — because most people
  who reach it arrived from a link someone sent them and are already part
  persuaded. Someone typing "reminder app for elderly parents" into a search
  engine has already decided they want software and is asking which one, and
  that search had no page here to land on. This one answers it in its own words:
  what a reminder app has to do when the person needing reminding and the person
  arranging it are not in the same house, how Remindly does each, what it runs
  on, and what comes back to the caregiver. It asks three questions of its own —
  is it worth it if they only take one tablet, will they find it patronising,
  what if it does not suit us — and publishes no `FAQPage`: `/faq` keeps that
  graph. Two pages of ours bidding for the same informational search compete
  with each other, and rewording the questions does not separate them, because
  what competes is the intent behind them. Held to the same claims as the rest
  of the site: "marked done", never "taken", and the page-must-stay-open
  limitation stated rather than buried.
- **A count of public page views, that records nobody**: the marketing pages set
  no analytics cookie and write no Ahoy visit, which is what makes the privacy
  policy true — and it left us unable to answer the only question that mattered
  after posting about Remindly on a forum: did it send nobody, or send people
  who bounced? Those call for opposite responses, and the fallback of grepping
  the server logs holds about a week. `PageCount` keeps one row per day per
  page, referring site, campaign tag and human/bot, with a counter. No visitor
  id, no IP address, no user agent, no cookie: the user agent is read to
  classify the request and thrown away, and a referrer is reduced to its host
  because referrer paths carry search terms. A `?from=` tag on a link we share
  survives forums that strip the referrer. Readable at **Admin → Traffic**, and
  deleted after 90 days by `PruneAnalyticsJob`, which is what the privacy policy
  promises. The policy is updated to describe exactly what is now kept.
- **The site can be found**: `/sitemap.xml`, generated from the routes and the
  posts on disk rather than kept as a static file, and advertised in
  `robots.txt`. `SoftwareApplication` structured data declaring a price of 0 —
  which is what lets a result carry a "free" label — plus `og:image` and
  `twitter:card`, without which every shared link rendered as a bare grey box.
- **`/faq`**: the questions caregivers type into a search engine, with
  `FAQPage` structured data so answers can surface directly in results.
  Questions and answers render from one source, because Google drops a
  `FAQPage` whose questions are not also visible on the page.
- **Blog at `/blog`**: posts are Markdown files in `backend/content/posts` with
  YAML front matter — no database table, no admin UI. Publishing is adding a
  file; the index, the sitemap and the `Article` structured data all pick it up.
  A `published_on` in the future is a draft.
- **Printable daily routine sheet at `/routine_sheet`**: one page for the fridge
  door, deliberately not gated behind the mailing list.
- **Mailing list**: signup on the public pages, with the routine sheet emailed
  on joining, and a notification to us naming the page that earned the address.
- **Product screenshots on the homepage**: real captures of the voice reminders
  page and the caregiver task list, scripted so they can be regenerated when the
  UI changes (`backend/script/marketing_screenshots`).
- **It says that it is free**: in the title of every page written to be landed
  on, a badge beside the logo, and a "why is it free — what's the catch?" FAQ
  entry, since answering the suspicion is worth more than repeating the word.
- **Free printable caregiver checklist at `/caregiver_checklist`**: a one-page
  weekly sheet with a box for each day — morning, through the day, evening, plus
  the weekly things that quietly cause a crisis if nobody looks. Ungated, like
  the routine sheet: a free printable is the one asset here that a senior centre
  or a caregiver forum might link to, and backlinks are what a new domain lacks.
- **Two more blog posts**: building a medication routine that sticks, and what to
  check on daily when a parent lives alone.
- **Navigation at the top of every public page**: How it works, Questions and
  Blog. Someone arriving on a post from a search previously had no visible route
  anywhere except Sign in — the one thing they are not ready to do. Three links,
  not the footer's seven, and no JavaScript: they stack under the logo on a
  narrow screen rather than hiding behind a menu.
- **`Organization` and `WebSite` structured data on every public page**, which is
  the association search engines use to tie a domain, a name and a support
  address together. Nothing declared it before.

### Changed
- **All mail now sends from `hello@remindly.care`**, defined once on
  `ApplicationMailer`. Seven of the eight mailers previously fell back to
  `noreply@remindly.app` — a domain that is not ours and that Postmark rejects
  outright — or sent from a personal address on another domain. Who receives
  contact submissions and subscriber notices stays configurable.
- **The task list shows a senior's name** rather than their email address.

### Fixed
- **Saving your profile could move you to UTC-12.** The timezone column had
  drifted into holding two spellings of the same thing — IANA identifiers
  (`America/New_York`, the column default) and Rails zone names (`Eastern Time
  (US & Canada)`, what the profile form submitted). Nothing ever failed on it,
  because every read goes through `ActiveSupport::TimeZone[]` and that accepts
  either, which is exactly why the mixture sat there unnoticed. The round trip
  is where it broke: the select's option values were Rails names, so a user
  whose column held the IANA default matched no option at all, the browser fell
  back to the first entry in the list — International Date Line West — and
  saving the form wrote it back. Changing your name moved you seventeen hours
  off Eastern, and in an app whose entire job is firing reminders at the right
  moment, that means every reminder lands on the wrong day. It happened to the
  first real signup, on her first day, and raised nothing anywhere. Zones are
  now normalized to the identifier on write, a zone that resolves to nothing is
  rejected instead of stored, and the select offers the same identifiers it
  stores so the round trip closes. A migration brings the existing rows across.
- **The traffic counter was calling scanners people.** Two days after shipping,
  the human figure was overstating by roughly two and a half times: 43 "human"
  views on 10 August against 18 favicon fetches, which is the number of requests
  a real browser actually made. The cause was the classifier being a denylist
  only, so anything without a recognisable bot token counted as a person —
  including a scanner sending `http://remindly.care/wp-admin/install.php?step=1`
  *as its user agent*. It now has to look like a browser to be counted as one,
  and the denylist still runs first because bingbot advertises itself inside an
  otherwise complete Chrome user agent and would sail through an allowlist
  alone. Against the user agents actually observed in production this moves 17
  of 55 out of the human column. It does not — and cannot — see a scraper that
  sends a convincing browser user agent; separating those would need a
  per-visitor identifier, which is the one thing these pages refuse to store.
  Rows written before this change keep their old classification, because the
  user agent was never stored. The allowlist counts an iOS web view as a
  browser even when it carries no Safari token, because a link tapped inside
  the Facebook app is exactly how the traffic this measures arrives.
- **Production could not boot, and CI could not have known.** A deploy failed
  with `NameError: uninitialized constant MailDeliveryJob` — the container
  exited 1 and never became healthy. Kamal kept the previous version serving, so
  there was no outage, but nothing shipped.
  `config/initializers/postmark.rb` touched `ActionMailer::Base` during
  initialization, which fires the `on_load` hook and constantizes the configured
  `delivery_job` before autoloading can resolve a constant from `app/`. The
  initializer was pure duplication — `config/environments/production.rb` already
  sets both `delivery_method` and `postmark_settings` — so deleting it is the
  whole fix. It was also wrapped in `if Rails.env.production?`, meaning its
  contents ran in exactly one environment, and that environment was the one no
  test and no CI job had ever started: 407 green specs against an app that could
  not start. CI now boots the production environment on every PR, using
  `SECRET_KEY_BASE_DUMMY` so it needs no secrets.
- **The coverage gap email arrives in the morning, not at 4am.** Schedules in
  `config/recurring.yml` are UTC, because `config.time_zone` is left at its
  default — which is not obvious when writing "8am". This job emails a caregiver
  to say nobody is scheduled to look after their parent on an upcoming day, and
  at 8am UTC it landed at 4am Eastern and 1am Pacific, buried under overnight
  mail by the time anyone was awake to act on it. Now `0 12 * * *` — 8am Eastern
  in summer, 7am in winter. A new spec guards the whole file, because a mistake
  in it is silent by construction: a schedule that does not parse, or a class
  that does not exist, means the task simply never runs, which looks exactly like
  a feature nobody uses.
- **Stop mailing addresses that no longer exist.** `CheckCoverageGapsJob` mailed
  two demo accounts every morning from 24 July to 9 August — 44 failed jobs,
  every one a `Postmark::InactiveRecipientError`. Both addresses had hard
  bounced ("unknown user, mailbox not found"), after which Postmark marks an
  address inactive and refuses every later send. Nothing was broken in the job;
  it was told to email people who do not exist, and had nowhere to record that
  it had been refused, so it rediscovered the fact daily. The exposure was real:
  aiming mail at mailboxes that are not there is what erodes a sending
  reputation, and every message now leaves the same address that carries
  magic-link logins — so the eventual cost of ignoring it is that nobody can log
  in. Delivery failures Postmark declares permanent are now discarded rather
  than retried (its own `retry?` says so), the address is recorded on the user,
  and notification mail skips it thereafter. In-app notifications are
  deliberately still created: a dead mailbox is no reason to hide a coverage gap
  from someone inside the app.
- **Public pages no longer record analytics visits.** `/faq`,
  `/routine_sheet`, `/blog` and every post were logging an IP, referrer and
  device for each anonymous reader while the privacy policy said public pages
  were not tracked. The exclusion now derives from the same list the sitemap is
  built from, so a page is public in both places or in neither.
- **The privacy policy discloses the mailing list** — what is stored, what it is
  used for, that Postmark sees it, and how to come off it.
- **Signing up twice no longer 500s.** Two concurrent requests for the same
  address could both pass the lookup before either committed.
- **The welcome email's replies reach a person.** It asks people to reply in
  order to stop, and was sending from an unmonitored `noreply@` address.
- **Tables in blog posts render properly** — cells had no padding and ran into
  one another.
- **Printing the routine sheet keeps its full-size handwriting rows.** Print
  density rules added for the checklist were global and shrank them from 2.6rem
  to 1.8rem — smaller boxes to write in, on a sheet made to be written on.
- **The blog is called "Blog" and the FAQ is called "FAQ"** rather than "Writing"
  and "Questions", both of which were chosen for tone at the cost of being
  scannable — people look for the word they expect, and the FAQ page's own title
  already used the conventional one.
- **`/blog` has a title worth showing in a search result** — it was "Writing",
  eighteen characters with no indication of what the writing is about.

## [0.5.0] - 2026-07-19

### Added
- **Marketing homepage at `/`**: the site had no indexable homepage — `/` was
  `dashboard#index` behind `authenticate!`, so it redirected to `/login` and
  Search Console reported it as "Page with redirect". Logged-out visitors now
  get a marketing page; signed-in users still go straight to `/dashboard`. It
  uses its own layout with inlined CSS, so it loads no third-party assets and
  sets no session cookie. It also links `/how_to`, which nothing linked to
  before.
- **Tap-to-start overlay when voice is locked**: browsers refuse
  `speechSynthesis` until the user has interacted with the page, and on iOS that
  applies after every load — including reloads iOS performs on its own. A page
  that cannot speak looked identical to one with nothing to say. The overlay
  makes the requirement explicit and is skipped for anyone who has turned voice
  announcements off.
- **`PruneAnalyticsJob`**: 90-day retention for Ahoy visits and events, nightly.
  `visitor_duration` only governed the cookie, so nothing removed the rows and
  the oldest visit in production held an IP address 270 days old. Undated rows
  count as expired, since a row with no timestamp can never be shown to be
  recent.
- **CI that actually runs**: tests, Brakeman and RuboCop on every PR. The
  workflow had lived at `backend/.github/workflows/ci.yml`, a directory GitHub
  Actions never reads, so no pull request in this repository had ever reported a
  check.

### Changed
- **Retired the standalone voice client**: three copies of the voice logic
  existed (`clients/web/`, `backend/public/client/`, and
  `backend/public/voice_reminders.js`). Only the last is reachable by seniors,
  and the duplication caused a day of voice fixes to land in a client nobody
  used. `/client/*` now redirects, carrying legacy magic-link tokens through to
  `/login/verify` so links in already-sent emails keep working.
- **Public pages no longer identify anonymous readers**: `/` and `/how_to`
  record no analytics visit and leave no tracking cookie. Everything behind the
  login still tracks. `visitor_duration` drops from 2 years to 30 days.
- **Cleared 604 RuboCop offenses** and enabled the lint job, so the rule holds
  from here rather than drifting.
- README, CLAUDE.md and the deployment guide rewritten: they described
  `clients/web` on port 8080 as the senior interface, which is not what is
  deployed and cost a day of work aimed at the wrong client.

### Fixed
- **Seniors could not acknowledge reminders**: `AcknowledgementsController`
  inherited from `WebController`, whose CSRF check rejected the voice client's
  Bearer request with 422 before it reached the database. Moving to
  `ApplicationController` then broke the session-authenticated page instead. It
  now accepts either credential, with CSRF skipped only for the Bearer scheme.
- **Voice announcements failed silently on desktop**: unlock was gated on
  `isIOSDevice()`, but Chrome's autoplay policy refuses speech on any untouched
  page. Voice now starts locked everywhere, and a refused announcement is queued
  and spoken once the user interacts rather than being lost — it was marked
  delivered before `speak()` was called.
- **Snooze could move a reminder earlier**: the delay was measured from `now`
  regardless of when the reminder was due, so snoozing a 10:25 reminder at 10:00
  rescheduled it to 10:10. It is now measured from the later of the scheduled
  time and now, and is idempotent on retry.
- **Snooze is hidden until a reminder is due**, and the highlight is reserved
  for reminders that are actually due rather than applied to every card.
- **The dashboard nav was invisible on phones**: it was `hidden sm:flex` with no
  mobile menu, so a senior on a phone saw only Profile and Sign Out and could
  not reach their own reminders page.
- **Canonical URLs** across `remindly.anakhsoft.com`, `remindly.care` and
  `www.remindly.care`, resolving the duplicate-content report that prompted this
  work.
- The pending-approval screen said "contact an administrator" without naming
  one, leaving new users with no way to get their account enabled.

### Security
- **Internal documentation is no longer served from `public/`**: six files,
  roughly 1,100 lines of architecture and integration detail, were publicly
  readable. A spec now fails if any Markdown or dependency manifest reappears
  there.
- **The post-login redirect takes a destination from an allowlist**, not a URL,
  so a genuine Remindly login link cannot be crafted to deliver a signed-in user
  to somewhere else.


## [0.4.3] - 2026-05-03

### Fixed
- **Restore environment config clobbered by Rails 8.1 `app:update`**: The
  Rails 8.1 upgrade replaced `config/environments/production.rb` and
  `development.rb` with template defaults and dropped the project's
  customizations. Re-applied them:
  - Production: `assume_ssl` / `force_ssl` (HSTS + secure cookies),
    `solid_cache_store`, Solid Queue Active Job adapter (so `deliver_later`
    and `CheckCoverageGapsJob` work), Postmark delivery method,
    `raise_delivery_errors`, mailer host / from, `host_authorization` `/up`
    exclude, and the explicit hosts allowlist for `remindly.anakhsoft.com`,
    `remindly.care`, and `www.remindly.care`.
  - Development: `letter_opener` delivery method and mailer host port `5000`
    so dev magic-link emails open in the browser again.
- Drop the `bin/importmap audit` step from `config/ci.rb` since
  `importmap-rails` is not a dependency.


## [0.4.2] - 2026-05-03

### Fixed
- **Magic link host matches login origin**: Magic-link emails now point at the
  domain the user actually started from. Previously, a login begun on
  `remindly.care` emailed a `remindly.anakhsoft.com` link because the URL was
  always built from the configured `base_url`. Both `MagicController#request_link`
  (voice web client) and `SessionsController#request_magic_link` (caregiver
  dashboard) now pass `request.base_url` to the mailer, validated against an
  allowlist of known hosts; off-list hosts fall back to the configured `base_url`.


## [0.4.1] - 2026-04-03

### Added
- **Caregiver Invitation Emails**: Email notifications when caregivers invite other caregivers
  - Professional HTML and text email templates
  - Includes inviter name, senior name, and login link
  - Lists caregiver permissions and capabilities
  - Sent asynchronously via background job
  - Comprehensive test coverage for mailer


## [0.4.0] - 2026-01-09

### Added
- **Recurring Tasks**: Full support for recurring tasks with user-friendly UI
  - Daily, weekly, and monthly recurrence patterns
  - Visual pattern builder with live preview
  - Auto-generates RRULE in iCalendar format
  - Automatically expands into task instances for next 30 days
  - Parent-child relationship (template → instances)
  - Edit template to regenerate all future instances
  - Reuses existing Recurrence service from Reminders
  
- **Open-Ended Tasks**: Tasks without specific scheduled dates
  - Easy checkbox toggle: "Make this an open-ended task"
  - Auto-hides date field when marked as open-ended
  - Smart default (tomorrow at 9 AM) when converting to scheduled
  - Purple badge display throughout UI
  - Separate section on tasks index showing open-ended tasks
  - Filter option to view all open-ended tasks
  - Caregivers can claim when available
  
- **Blocking Unavailable Times**: Prevent task scheduling during unavailable periods
  - Create time blocks with start/end times and optional reason
  - Recurring patterns: Daily, Weekdays, Weekends, Weekly, Every Night
  - One-time blocks for specific dates/times
  - Active/inactive toggle to temporarily disable blocks
  - Automatic validation prevents task scheduling during blocked times
  - Overlap prevention for time blocks
  - Detailed error messages showing conflict details
  - Full CRUD interface for managing time blocks
  
- Database migrations:
  - Added `rrule`, `tz`, `start_time`, `parent_task_id` to tasks table
  - Made `scheduled_at` nullable in tasks table
  - Created `time_blocks` table with full recurrence support

### Changed
- Task model now supports optional `scheduled_at` for open-ended tasks
- Task form includes recurrence pattern builder with dropdown selectors
- Task validation now checks against blocked time periods
- Tasks index page reorganized with open-ended tasks section
- Added "🚫 Blocked Times" button to tasks navigation

### Fixed
- All views now handle nil `scheduled_at` values correctly
- Task assignment notifications work with open-ended tasks
- Senior dashboard displays open-ended tasks without errors
- Task show view handles tasks without scheduled dates

### Security
- Time block access restricted to senior and their caregivers
- Validation prevents overlapping time blocks for security


## [0.3.4] - 2025-11-25

### Added
- Automatic iPad voice-unlock listeners for the web client and Rails dashboard (voice unlock attempts fire after any tap)
- Enable Voice button in Advanced Options for the Rails dashboard (mirrors standalone web client)
- ⚙️ Settings button in the dashboard Advanced Options row so caregivers can access audio controls

### Changed
- Voice reminders now reuse the same unlock flow across hosted and standalone clients for consistency
- Improved caregiver-facing UI to surface voice settings and unlock affordance

### Fixed
- iPad reminders no longer stay silent until caregivers find a hidden enable control
- Voice unlock instructions now appear wherever the button exists (web client + dashboard)

### Security
- 


## [0.3.3] - 2025-11-10

### Added
- Calendar view for caregiver availability with toggle between list and calendar views
- Color-coded monthly calendar (green for available days, white for unavailable, gray for past)
- Display both start and end times on calendar days
- Month navigation (previous/next) for availability calendar
- Click-to-add functionality on calendar days
- Task unassign feature - caregivers can unassign themselves from tasks
- Task assignment notifications - assigned caregiver always notified
- Notification preference for caregivers to opt-in to notifications when tasks assigned to others
- New notification types: `task_available` and `task_assigned`
- "Unassign Me" button in task detail view with confirmation dialog

### Changed
- Updated how-to pages to clarify acknowledgment tracking (care receivers can acknowledge/snooze)
- Improved notification system to exclude caregiver from their own unassignment notification
- Enhanced availability view with persistent view preference (localStorage)

### Fixed
- Migration version updated to match Rails 8.0


## [0.3.2] - 2025-11-09

### Added
- Automated tests for critical bug fixes (11 tests, 45 assertions)
- Test infrastructure (test_helper.rb, fixtures)
- TEST_SUMMARY.md documentation

### Changed
- Improved performance: cached dev user queries to avoid N+1
- Improved performance: optimized coverage view with nested hash lookup (O(1))
- Use Date.current instead of Date.today for time zone consistency
- Enhanced error handling: replaced rescue nil with explicit logging

### Fixed
- **CRITICAL:** Fixed overlap detection bug in CaregiverAvailability (was checking end_time twice)
- **CRITICAL:** Fixed FeatureFlag.all method (was passing env_var instead of feature_key)
- Removed redundant where.not(id: nil) checks on primary keys
- Fixed misleading comments in CheckCoverageGapsJob
- Updated FEATURE_FLAGS.md last modified date

### Security
- N/A


## [0.3.1] - 2025-11-04

### Fixed
- Added comprehensive null checks for all DOM elements in voice_reminders.js to prevent runtime errors
- Fixed API filter to return both pending and acknowledged reminders for proper completion status display
- Re-enabled raise_on_missing_callback_actions in development environment for better error detection
- Added documentation comment explaining slow voice rate default (40% speed optimized for seniors)


## [0.3.0] - 2025-11-03

### Added
- Voice Reminders page with automatic text-to-speech announcements
- Browser-based speech synthesis for reminder announcements
- Done, Snooze (10 min), and Skip actions for reminders
- Acknowledgements system to track reminder completion
- Senior-friendly simplified UI with larger text and clearer layout
- Cross-browser speech synthesis support
- Timezone-aware reminder scheduling and display

### Changed
- Simplified Senior Dashboard to show only pending reminders prominently
- Completed reminders now collapsed in dropdown to reduce clutter
- Increased font sizes and button sizes for better accessibility
- Only announce reminder titles (not notes) to keep announcements concise
- Voice Reminders page uses timestamp-based cache busting for JavaScript

### Fixed
- Timezone display issues in new reminder form
- Voice announcements now work correctly across all modern browsers
- Duplicate announcement prevention
- JavaScript null reference errors in stats updates


## [0.2.8] - 2025-11-03

### Added
- App version display on public pages (login, how_to, contact) for easier debugging
- App version display in dashboard header for logged-in users

### Changed
- 

### Fixed
- Fixed NoMethodError when displaying app version on public pages (use APP_VERSION constant)

### Security
- 


## [0.2.7] - 2025-10-30

### Added
- 

### Changed
- 

### Fixed
- Fixed iPad mini icon sizing with additional responsive breakpoints
- Added md: breakpoint for medium tablets (including iPad mini)
- Icons now scale: h-4 w-4 (mobile) → h-5 w-5 (small tablets) → h-6 w-6 (medium tablets) → h-8-12 w-8-12 (desktop)
- Fixed task action icons, senior dashboard stats icons, and empty state icons
- Ensures proper sizing on iPad mini 7.9" displays

### Security
- 


## [0.2.6] - 2025-10-30

### Added
- 

### Changed
- 

### Fixed
- Fixed responsive icon sizing on tablets and iPads
- Icons now scale appropriately: smaller on mobile, medium on small tablets, full size on desktop
- Updated viewport meta tag for better tablet behavior
- Added responsive text sizing for main headings

### Security
- 


## [0.2.5] - 2025-10-24

### Added
- **How To page** with comprehensive descriptions of main features
  - Reminders functionality with custom schedules, categories, and voice announcements
  - Tasks functionality with assignment, scheduling, and status tracking
  - Browser compatibility note for voice announcements (all modern browsers supported)
  - Three video tutorial links:
    - How to Log In (magic link authentication)
    - How a Senior starts a request to connect with a Caregiver
    - How a Caregiver connects with a Senior
- **Contact Us page** with form for user feedback and support
  - Form fields: name, email, and message (all required)
  - Email notifications sent to admin_email via ContactMailer
  - HTML and text email templates with professional formatting
  - Reply-to set to submitter's email for easy responses
- **Navigation links** for How To and Contact Us pages in dashboard header

### Changed
- **Version management improved** - Version is now fetched dynamically via `/version` API endpoint
  - Web client automatically displays current version without hardcoding
  - Simplified bump_version.sh script (no longer needs to update HTML files)
  - Single source of truth for version (VERSION file + deploy.yml)

### Fixed
- 

### Security
-


## [0.2.4] - 2025-10-23

### Changed
- **Code quality improvements from PR feedback**
  - Use current time as default for new reminders (instead of hardcoded 09:00)
  - Simplified JSON request body parsing in magic_controller
  - Removed redundant getDefaultApiUrl() call in web client
  - Moved helper method inside namespace to avoid global pollution

### Fixed
- **Documentation improvements**
  - Clarified cron time format (12-hour input vs 24-hour output)
  - Use environment variables in cron documentation instead of hardcoded values


## [0.2.3] - 2025-10-23

### Added
- **Automated version bump script**
  - `bump_version.sh` now updates deploy.yml APP_VERSION
  - Auto-creates CHANGELOG.md entry template
  - Added deployment reminder to DEPLOYMENT_CHECKLIST.md

### Changed
- **Version management improvements**
  - Version fallback now checks multiple sources (monorepo VERSION, Rails VERSION, ENV)
  - Better documentation of version priority order
  - Removed hardcoded version fallbacks

### Fixed
- **Production version display**
  - Fixed "unknown" version in production
  - Added APP_VERSION to deployment environment variables


## [0.2.2] - 2025-10-23

### Fixed
- **Web client magic link routing**
  - Fixed web client to send `client=web` parameter
  - Magic links now correctly point to `/client/` instead of `/magic/verify`
  - Updated cache buster to force browser reload of updated JavaScript
  - Fixed version display in web client UI

## [0.2.1] - 2025-10-23

### Security
- **Improved magic link security**
  - Web client now uses POST instead of GET for token verification
  - Prevents token exposure in server logs, browser history, and referer headers
  - Backend supports both GET (email links) and POST (API) for backward compatibility

### Changed
- **Simplified web client detection**
  - Removed fragile referer-based detection
  - Now uses only explicit `client=web` parameter
  - More reliable and maintainable

### Fixed
- **Cross-platform compatibility**
  - Fixed `bump_version.sh` to work on both macOS and Linux
  - Detects OS and uses appropriate sed syntax
- **Code quality improvements**
  - Fixed misleading comments in magic_mailer.rb
  - Added detailed rationale for bot tracking in ahoy.rb
  - Extracted recipient email resolution into reusable helper method
  - Documented timezone assumption in cron schedule

### Added
- Test scripts for verifying magic link functionality
  - `test_magic_links.sh` - Tests different client types
  - `test_magic_post.sh` - Verifies GET and POST methods

## [0.2] - 2025-10-23

### Added
- **Audit Logging System** with Ahoy gem
  - Track all login/logout events with IP addresses and user agents
  - Admin-only UI for viewing audit logs at `/admin/audit_logs`
  - Filter audit logs by event type, user, and date range
  - Detailed event view with visit information
  - Statistics dashboard showing success/fail counts

- **Automated Daily Audit Reports**
  - Email reports sent automatically at 10 PM daily
  - Beautiful HTML email template with statistics
  - Plain text email fallback
  - Summary statistics (total events, success/fail/logout counts)
  - Activity grouped by user with role badges
  - Complete event listing with timestamps, methods, and IPs
  - Manual report generation: `rails audit:daily_report`
  - Custom date reports: `rails audit:report_for_date[date,email]`
  - Preview command: `rails audit:preview`

- **Cron Job Management**
  - Whenever gem for cron job scheduling
  - Configured to run daily at 10 PM
  - Comprehensive setup documentation

### Documentation
- `AHOY_AUDIT_GUIDE.md` - Complete audit logging guide
- `AUDIT_REPORTS_GUIDE.md` - Email reports documentation
- `CRON_SETUP.md` - Cron job setup instructions

### Technical
- Added `ahoy_matey` gem (~> 5.2)
- Added `whenever` gem (~> 1.0)
- Added `kaminari` gem (~> 1.2) for pagination
- Created `ahoy_visits` and `ahoy_events` database tables
- User model associations for visits and events

## [0.1] - 2025-10-22

### Added
- **Initial Release**
- Core reminder system for seniors
- Magic link authentication (email-based, passwordless)
- Caregiver pairing system with token-based linking
- Task management for caregivers and seniors
- Voice web client for seniors
- Dashboard for caregivers
- User roles: Senior, Caregiver, Admin
- Admin user management interface
- Email delivery via Postmark
- SQLite database
- Docker deployment with Kamal
- Production deployment on DigitalOcean

### Features
- **Reminders**
  - Create, edit, delete reminders
  - Recurring reminders with ice_cube
  - Reminder acknowledgements
  - Snooze functionality
  - Today's reminders view

- **Authentication**
  - Magic link login (web and API)
  - JWT token-based sessions
  - Dev mode quick login
  - Session management

- **Caregiver Features**
  - Pair with seniors using tokens
  - View senior's reminder activity
  - Create reminders for seniors
  - Task assignments
  - Availability scheduling

- **Admin Features**
  - User management
  - Role assignment
  - View all users and relationships

### Technical Stack
- Ruby on Rails 8.0.3
- Ruby 3.3.5
- SQLite database
- Puma web server
- Postmark for emails
- JWT for authentication
- Docker containerization
- Kamal deployment
- TailwindCSS for styling

### Documentation
- Phase 5 Authentication Guide
- Sprint 5 Implementation Guide
- Setup instructions
