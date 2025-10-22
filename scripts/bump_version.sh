#!/bin/bash
# Script to bump version number across all files

# Read current version
CURRENT_VERSION=$(cat VERSION)
echo "Current version: $CURRENT_VERSION"

# Ask for new version
read -p "Enter new version (e.g., 0.2): " NEW_VERSION

if [ -z "$NEW_VERSION" ]; then
    echo "No version provided. Exiting."
    exit 1
fi

# Update VERSION file
echo "$NEW_VERSION" > VERSION

# Update web client
sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" clients/web/index.html
sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/public/client/index.html

# Update dashboard layout
sed -i '' "s/v$CURRENT_VERSION/v$NEW_VERSION/g" backend/app/views/layouts/dashboard.html.erb

echo "Version bumped to $NEW_VERSION"
echo "Files updated:"
echo "  - VERSION"
echo "  - clients/web/index.html"
echo "  - backend/public/client/index.html"
echo "  - backend/app/views/layouts/dashboard.html.erb"
echo ""
echo "Don't forget to commit these changes!"
