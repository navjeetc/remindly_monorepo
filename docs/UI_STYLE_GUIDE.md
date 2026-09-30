# UI style guide

Read this before adding or changing anything a person fills in or presses on
a Remindly page. It covers the web app: the dashboard, sign-in and the voice
page. The public marketing pages have their own inline CSS and are out of
scope (see "Public pages" below).

The people using this are caregivers in a hurry and the older adults they
look after. Nearly every rule below came from someone missing a control,
misreading one, or pressing the wrong thing. A control should be obvious to
someone who isn't looking closely.

The styles live in one file, `backend/app/views/shared/_ui_styles.css.erb`,
which the dashboard layout, the sign-in page and the voice layout all
include. `spec/requests/form_fields_look_like_fields_spec.rb` enforces most
of this guide, so a page that breaks a rule fails CI.

## Fields

Every text box, email/number/date/time input, text area and drop-down uses
the `field` class:

```erb
<%= f.text_field :title, class: "field mt-1 block w-full" %>
<%= f.select :category, options, {}, class: "field mt-1 block w-full" %>
```

`field` sets how the control **looks**: a 2px grey border, a white fill,
padding, 1rem text and a blue focus ring. Where it **sits** (width, margins,
`block`) stays as Tailwind utilities beside it. Don't add border, rounded,
shadow, padding or text-size utilities to a field; the class already has them.

- **Compact fields** (a drop-down inline in a sentence or a table row) may
  add `text-sm py-1`. Utilities override `field` because the Tailwind CDN
  loads after it.
- **Read-only fields you copy from** (a device link, a message to send) use
  `field` too, and turn grey on their own via `[readonly]`. Long values may
  add `text-sm font-mono`.
- **Checkboxes, radios and range sliders** are not fields and don't get the
  class.

Why: fields were once invisible (a border colour with no border width), and
later a dozen variants of a faint 1px line with no padding. A caregiver typed
a reminder's title into the notes box, and drop-downs read as plain text.

## Buttons

Every button, and every link styled as one, uses `button` plus exactly one
variant. The spec holds every real button (`button_to`, a submit, a
`<button>`) to this whatever it looks like, and any link dressed as a button
(padding, a fill or border, rounded corners):

| Variant | Looks like | Use it for |
|---|---|---|
| `button-primary` | solid blue, white text | The main action on the page or form: Create, Save, Send. One per form. |
| `button-secondary` | solid grey | Everything else: Cancel, Edit, Back, Filter, View. |
| `button-danger` | light red, red text | Anything that removes, revokes or switches something off: Delete, Remove Access, Stop this link, Unlink. |

```erb
<%= f.submit "Create Reminder", class: "button button-primary" %>
<%= link_to "Cancel", back_path, class: "button button-secondary" %>
<%= button_to "Stop this link", path, class: "button button-danger", title: "…" %>
```

- **Buttons are always filled, never white with an outline.** A white box
  with a grey border is what a field looks like: "Replace this link" and
  "Stop this link" were taken for form fields. The spec fails on any button
  drawn that way.
- **A button is as tall as a field** (`min-height: 2.75rem`), so a button next
  to a field lines up with it. That is also the smallest comfortable tap
  target. Compact buttons in a table row may add `px-3`, but keep the height.
- A **disabled** button (`disabled: true`) fades itself out; don't add grey
  utilities for that.
- On the **voice page** the same classes render with body-size text, because
  the care receiver presses them. That override lives in the voice layout.
- A button that destroys, cancels or replaces something asks first, with a
  plain `onclick`:

  ```erb
  onclick: "return confirm('#{j "Delete this reminder? This cannot be undone."}')"
  ```

  **Never `data: { confirm: }` or `data: { turbo_confirm: }`.** No layout
  loads Turbo or Rails UJS, so those attributes are never read and the button
  acts on one click while looking as if it would ask. Delete Reminder, Delete
  Task, Unlink and Disconnect all did exactly that. The spec fails on either.

A few controls are deliberately not ordinary buttons. Each is listed in the
spec's `CUSTOM_CONTROLS`, matched by a piece of its source and given a reason:
the quick-pick date chips on bulk availability, the green and purple role
links on How-To (coloured to match their sections), the List/Calendar switch,
the role cards and the inline "Sign out" text link on the welcome page, the ×
that closes the voice settings dialog, the green Mark Complete beside the
blue Start Task, and a development-only trigger.

The care receiver's reminder card is built in `public/voice_reminders.js`,
which the view scan can't see. Its Done and Snooze buttons are deliberately
oversized, but the spec still fails if a button there is white with a grey
border. Don't add new colours without a
reason that goes in that list.

## Tooltips

A button gets a `title` tooltip when its label alone doesn't tell you what
will happen, and always when it can't be undone:

```erb
title: "Switch this link off. Their device stops showing reminders until you create a new link."
```

Say what happens and to whom, in one or two plain sentences. Don't restate
the label. `title` tooltips only appear on hover, after about a second, and
never on touch screens, so anything a person must know before pressing
belongs in the text beside the button, not only in the tooltip.

## Labels

- Every field has a visible label. Placeholders are examples ("e.g., Morning
  pills"), never the only label.
- Mark optional fields "(Optional)".
- **No emoji in labels.** "✅ Active" put a green tick beside a checkbox: a
  second checkmark when ticked, and a contradiction when not. The spec
  enforces this.

## Where the cursor starts

A form for **making** something new puts the cursor in the first field a
person types into, with `autofocus`:

```erb
<%= f.text_field :title, autofocus: @task.new_record?, class: "field mt-1 block w-full" %>
```

- It's the first field a person *types into*, not the first field on the
  page. On New Blocked Time the start and end arrive filled in, so the cursor
  goes to Reason even though it is optional.
- **Edit forms don't autofocus.** Someone opening an existing reminder is as
  likely there to change the time as the title. In a partial shared by new
  and edit, use `autofocus: @record.new_record?`.
- Skip it where the first field is a pre-filled date and nothing needs
  typing (availability).
- One `autofocus` per page.

## Emoji

An emoji is only worth adding if it tells you something the words next to it
don't. The 🚫 on the blocked-times pages repeated "Blocked" in the heading,
appeared again on every row, and a "forbidden" sign read as an error. None in
labels, none repeating a heading, none on every row of a list.

## Public pages

`/`, `/faq`, `/blog` and the other `PublicPage` pages use the `marketing`
layout, which inlines its own CSS and loads nothing from the dashboard (see
CLAUDE.md). Its mailing-list input already has a 2px border and padding.
Follow the same intent there, but in that layout's own CSS; don't include
`_ui_styles` on public pages.

## Exemptions

The spec lists every exemption with its reason. Current ones:

- the mailing-list box on public pages (marketing layout, own CSS);
- the six-digit code box on `/start`, which is deliberately far larger than
  any field;
- the development-only user switcher in the nav;
- the custom controls listed under Buttons above.

Public pages and emails are skipped entirely: they have their own inline CSS,
and their `.btn` and `button` classes are theirs.

Add one only with a reason that would satisfy the person trying to find the
control.

## One pitfall

`_ui_styles` is a `.css.erb` template, rendered with
`render partial: "shared/ui_styles", formats: :css`. As an `.html.erb`
partial it breaks in development: Rails wraps HTML partials in
`<!-- BEGIN … -->` comments, CSS doesn't treat those as comments, and the
first rule (`.field`) is silently dropped. Production looks fine, which is
what makes it easy to miss.
