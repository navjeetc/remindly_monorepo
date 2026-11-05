# Remindly backend: guide for AI coding agents

This is the Rails 8 API and web app for **Remindly**, a reminder service for
older adults and the family who care for them. It is an application, not the
Rails framework: an earlier version of this file was adapted from Rails' own
contributor guide, and its framework rules (Minitest under `test/`,
`bin/test`, component directories, `load_defaults` flags) never applied here.

The repository root `CLAUDE.md` is the full project guide: architecture, the
public-page rules, mail, the CRM, deployment. Read it before a non-trivial
change. This file holds the rules a reviewer most often needs.

## Tests: RSpec, under `spec/`

- The suite is **RSpec** (`spec/`, about 120 files). CI runs
  `bundle exec rspec` and nothing else, so a test anywhere else never runs.
- `test/` holds three old Minitest files that CI does not run. Don't add to it.
- Run everything with `bundle exec rspec`, or one file with
  `bundle exec rspec spec/path/to/file_spec.rb`.
- Request specs sign in with
  `post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }`.
- Some specs are guards that check every view or file for a rule (for example
  `form_fields_look_like_fields_spec.rb` and `public_assets_spec.rb`). A failure there means the change broke a project
  rule, not that the spec is wrong.
- To change a class attribute for one test, use `Object#with`
  (`require "active_support/core_ext/object/with"`) rather than saving and
  restoring it by hand, which leaks the change when the test fails midway:

  ```ruby
  SomeClass.with(setting: value) do
    # test code
  end
  ```

## CI

`.github/workflows/ci.yml` at the repository root runs on every PR:

- `test`: the RSpec suite
- `scan_ruby`: Brakeman (`bin/brakeman --no-pager`). It runs with
  `--ensure-latest`, so update the gem when it falls behind rather than removing
  the flag.
- `lint`: RuboCop (`bin/rubocop -f github`). Run `bundle exec rubocop` on the
  files you touch before pushing.
- `boot_production`: the app boots in production mode

## Code style

- Use `# frozen_string_literal: true` at the top of new Ruby files. Most
  existing files predate this rule and do not carry it; adding it to them
  wholesale was tried and rejected (#127), because freezing literals changes
  runtime behaviour and the gain does not justify the risk in working code.
  Generated files are exempt and cannot comply anyway: Rails rewrites
  `db/schema.rb` on every migration and regenerates `bin/*`.
- Rich models, plain CRUD controllers, and comments that say **why** a line is
  there. Many comments name the incident or PR that caused them; keep them
  when editing nearby.
- Web forms and buttons follow `docs/UI_STYLE_GUIDE.md`; a spec enforces it.

## Changelog

Add an entry to `CHANGELOG.md` **at the repository root** when fixing a bug or
adding a feature. There is one changelog.

- Put it under `## [Unreleased]`, creating that section if the last release has
  already been cut.
- Group under `### Added`, `### Changed`, `### Fixed` or `### Security`.
- Lead with a bold summary, then say **why**: what was broken, or what the
  change makes possible. The existing entries explain the reasoning, and that is
  the part worth copying.

Don't use the "Brief description, then `*Your Name*`" format. That is the Rails
framework's convention and no entry here has ever used it.

## Version bumps

Bump the version when a **significant feature** lands, not on a schedule and not
once a quarter. Minor for a real feature, on the precedent of 0.5.0 and 0.6.0;
patch for a fix.

```bash
./scripts/bump_version.sh 0.7.0
```

The script is the point: the version lives in three files — `VERSION`,
`backend/VERSION` and `backend/config/deploy.yml` — and doing it by hand while
missing `deploy.yml` is how production ends up reporting a stale number.

It also inserts an empty CHANGELOG template above `[Unreleased]`. Delete it. The
entries it asks for are the ones already written under `[Unreleased]` as each
change landed, so promote that heading to the release instead and leave a fresh
empty `[Unreleased]` above it.

**Why this matters more than housekeeping:** the version is printed in the
dashboard nav, on the login page, on contact and how-to, and returned by
`GET /version` — which is the first item in `docs/POST_DEPLOY_CHECKS.md`, read
to confirm a new image is actually live. A number that never moves makes that
check agree with itself whether the deploy worked or not. It is exactly why
0.5.0 was cut, and it happened again: 0.5.0 stood from 19 July through telephone
reminders, the critical flag, two call languages and twenty-odd merged PRs.

## Pull requests and issues

- Link a PR to the issue it resolves with `Fixes #N` in the description, and
  say so when it only partly addresses one.
- A PR that ships something a prospective user should hear about updates
  `docs/ONBOARDING_FEATURES.md`, or says why not (see `CLAUDE.md`).
