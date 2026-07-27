# Regenerating the marketing screenshots

The two images on the homepage (`public/screenshot-voice-reminders.webp` and
`public/screenshot-tasks.webp`) are captures of the **real running app**, not
mockups. They go stale whenever the voice reminders page or the task list
changes, and a stale screenshot on a marketing page is worse than none — it
promises an interface that no longer exists.

This regenerates them.

## Why it is scripted rather than done by hand

Three things have to be true of every capture, and all three are easy to forget:

1. **The data must be fictional.** The development database contains real email
   addresses. These images are published to a public page, so nothing captured
   from a real account can ever appear in one.
2. **The development chrome must be stripped.** The dashboard nav carries a
   user-switcher that exists only in development. Left in, it appears in the
   image as though it were a product feature.
3. **The voice page must be clicked through.** Browsers will not speak until
   someone has touched the screen, so `/voice_reminders` opens on a "Tap to
   start" gate. Screenshotting without clicking it captures the gate.

## Running it

Needs the dev server running and Python Playwright available. Playwright drives
the system Chrome, so there is no browser download.

```bash
# 1. Start the app (port 5000 is taken by AirPlay Receiver on macOS)
cd backend && bundle exec rails server -p 3000

# 2. Seed fictional demo data — prints the senior's id
bundle exec rails runner script/marketing_screenshots/demo_data.rb

# 3. Capture. Update SENIOR_ID in capture.py if step 2 printed a different one.
cd script/marketing_screenshots && python3 capture.py

# 4. Crop, resize and convert. WebP is ~4.5x smaller than PNG here, and this
#    page is the one that has to stay fast.
magick voice-raw.png -crop 1960x1650+0+0 +repage -resize 1400x -quality 82 \
  ../../public/screenshot-voice-reminders.webp
magick tasks-raw.png -resize 1400x -quality 82 \
  ../../public/screenshot-tasks.webp
```

The crop on the voice image ends just below the second reminder card. Adjust it
if the page layout changes — the aim is to show the heading, the count, and two
complete cards, never a card cut through the middle.

## After regenerating

`spec/requests/pages_spec.rb` asserts that both files exist, are same-origin,
carry alt text, and declare intrinsic dimensions. **If the image dimensions
change, update the `width` and `height` attributes in
`app/views/pages/home.html.erb`** — they are what stop the page jumping as the
images load, and a wrong value is worse than none.
