"""Capture real screenshots of the running app for the marketing page.

See README.md in this directory for how to run this and what to do afterwards.

One browser context per role, so the Rails session cookie survives between the
dev_login redirect and the page we actually want.

Two things are stripped before every capture:

  * the nav bar, which carries a development-only user switcher that would be
    confusing and is not part of the product, and
  * the version badge.

Everything else is the real running app with fictional demo data.
"""
from playwright.sync_api import sync_playwright

BASE = "http://localhost:3000"
SENIOR = "margaret@example.com"
CAREGIVER = "alex@example.com"
SENIOR_ID = 25

STRIP_CHROME = """
  document.querySelectorAll('nav').forEach(el => el.remove());
  document.querySelectorAll('div').forEach(el => {
    const t = el.textContent.trim();
    if (t.startsWith('Senior Dashboard Visibility')) el.style.display = 'none';
  });
  // Trim the generous top padding the nav used to sit above.
  const main = document.querySelector('main');
  if (main) main.style.paddingTop = '1.5rem';
"""


def capture(page, path, selector="main"):
    page.evaluate(STRIP_CHROME)
    page.wait_for_timeout(400)
    page.locator(selector).first.screenshot(path=path)
    print(path)


with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome")

    # --- Senior: the voice reminders page ---------------------------------
    # Tablet-shaped viewport, because that is what it actually sits on.
    ctx = browser.new_context(viewport={"width": 980, "height": 1500}, device_scale_factor=2)
    page = ctx.new_page()
    page.goto(f"{BASE}/dev_login?email={SENIOR}", wait_until="networkidle")
    page.goto(f"{BASE}/voice_reminders", wait_until="networkidle")

    # The audio-unlock gate. Browsers will not speak until someone has touched
    # the screen, so the real page shows this first — click through it to reach
    # the reminder list, which is what the image is actually about.
    for label in ["Turn on voice", "Tap to start"]:
        button = page.get_by_role("button", name=label)
        if button.count():
            button.first.click()
            break

    page.wait_for_timeout(3500)
    capture(page, "voice-raw.png")
    ctx.close()

    # --- Caregiver: task management ---------------------------------------
    ctx = browser.new_context(viewport={"width": 1180, "height": 1100}, device_scale_factor=2)
    page = ctx.new_page()
    page.goto(f"{BASE}/dev_login?email={CAREGIVER}", wait_until="networkidle")
    page.goto(f"{BASE}/seniors/{SENIOR_ID}/tasks", wait_until="networkidle")
    capture(page, "tasks-raw.png")
    ctx.close()

    browser.close()
