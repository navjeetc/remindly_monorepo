# Version Management

## Current Version
The current version is stored in the `VERSION` file at the root of the repository.

## Version Display Locations
- **Voice Web Client**: Top right corner of header (`/client/`)
- **Caregiver Dashboard**: Top right corner of navigation bar

## How to Bump Version

### Option 1: Using the Script (Recommended)
```bash
./scripts/bump_version.sh
```
This will prompt you for the new version and update all necessary files.

### Option 2: Manual Update
1. Update the `VERSION` file with the new version number
2. Update version in these files:
   - `clients/web/index.html` (line with `<span class="version">`)
   - `backend/public/client/index.html` (line with `<span class="version">`)
   - `backend/app/views/layouts/dashboard.html.erb` (line with version span)

3. Commit the changes:
```bash
git add VERSION clients/web/index.html backend/public/client/index.html backend/app/views/layouts/dashboard.html.erb
git commit -m "Bump version to X.Y"
```

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
