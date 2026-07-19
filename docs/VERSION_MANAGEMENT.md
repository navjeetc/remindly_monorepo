# Version Management

## Current Version
The current version is stored in the `VERSION` file at the root of the repository.

## Version Display Locations
Every one of these renders `<%= APP_VERSION %>`, so none of them needs editing
when the version changes:

- **Dashboard and Voice Reminders**: navigation bar (`layouts/dashboard.html.erb`)
- **Login**: below the sign-in form (`sessions/new.html.erb`)
- **Contact** and **How To** pages
- **`GET /version`**: returns it as JSON, which is how a deploy can be checked

## How to Bump Version

### Option 1: Using the Script (Recommended)
```bash
./scripts/bump_version.sh
```
This will prompt you for the new version and update all necessary files.

### Option 2: Manual Update
Views render `<%= APP_VERSION %>`, which `backend/config/initializers/version.rb`
reads from the `VERSION` file — no view hardcodes a version string. Three files
hold the value:

1. `VERSION` at the repo root
2. `backend/VERSION`, a copy the production image reads
3. `backend/config/deploy.yml`, which pins `APP_VERSION` for the deployed container

```bash
git add VERSION backend/VERSION backend/config/deploy.yml
git commit -m "Bump version to X.Y"
```

The script above updates all three; doing it by hand and missing `deploy.yml` is
how production ends up reporting a stale version at `/version`.

## Version Numbering
- **Major.Minor** format (e.g., 0.1, 0.2, 1.0)
- Increment **Minor** for regular updates and bug fixes
- Increment **Major** for significant feature releases

## Deployment
After bumping the version and committing:
```bash
cd backend
kamal deploy
```
