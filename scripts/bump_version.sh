#!/bin/bash
# Script to bump version number across all files
# Usage: ./scripts/bump_version.sh [new_version]
# Example: ./scripts/bump_version.sh 0.3.0

set -e  # Exit on error

# Read current version
CURRENT_VERSION=$(cat VERSION)
echo "📦 Current version: $CURRENT_VERSION"
echo ""

# Get new version from argument or prompt
if [ -n "$1" ]; then
    NEW_VERSION="$1"
else
    read -p "Enter new version (e.g., 0.3.0): " NEW_VERSION
fi

if [ -z "$NEW_VERSION" ]; then
    echo "❌ No version provided. Exiting."
    exit 1
fi

echo "🔄 Bumping version from $CURRENT_VERSION to $NEW_VERSION..."
echo ""

# Update VERSION file
echo "$NEW_VERSION" > VERSION
echo "✅ Updated VERSION file"

# Update deploy.yml APP_VERSION
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/APP_VERSION: \"$CURRENT_VERSION\"/APP_VERSION: \"$NEW_VERSION\"/g" backend/config/deploy.yml
    sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" clients/web/index.html
    sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/public/client/index.html
    sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/app/views/layouts/dashboard.html.erb
else
    # Linux
    sed -i "s/APP_VERSION: \"$CURRENT_VERSION\"/APP_VERSION: \"$NEW_VERSION\"/g" backend/config/deploy.yml
    sed -i "s/v$CURRENT_VERSION/v$NEW_VERSION/g" clients/web/index.html
    sed -i "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/public/client/index.html
    sed -i "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/app/views/layouts/dashboard.html.erb
fi
echo "✅ Updated deploy.yml APP_VERSION"
echo "✅ Updated client HTML files"

# Create CHANGELOG entry template
TODAY=$(date +%Y-%m-%d)
CHANGELOG_ENTRY="## [$NEW_VERSION] - $TODAY

### Added
- 

### Changed
- 

### Fixed
- 

### Security
- 

"

# Insert new version at the top of CHANGELOG (after header)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - insert after line 7 (after the header)
    sed -i '' "7a\\
$CHANGELOG_ENTRY
" CHANGELOG.md
else
    # Linux
    sed -i "7a\\$CHANGELOG_ENTRY" CHANGELOG.md
fi
echo "✅ Created CHANGELOG.md entry template"

echo ""
echo "📋 Summary of changes:"
echo "  ✓ VERSION: $CURRENT_VERSION → $NEW_VERSION"
echo "  ✓ backend/config/deploy.yml: APP_VERSION updated"
echo "  ✓ clients/web/index.html: version updated"
echo "  ✓ backend/public/client/index.html: version updated"
echo "  ✓ backend/app/views/layouts/dashboard.html.erb: version updated"
echo "  ✓ CHANGELOG.md: new version entry created"
echo ""
echo "📝 Next steps:"
echo "  1. Edit CHANGELOG.md and fill in the changes"
echo "  2. Review the changes: git diff"
echo "  3. Commit: git add -A && git commit -m \"Bump version to $NEW_VERSION\""
echo "  4. Deploy: cd backend && kamal deploy"
echo ""
