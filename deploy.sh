#!/bin/bash

# Load asdf
if [ -n "$ASDF_DIR" ] && [ -f "$ASDF_DIR/asdf.sh" ]; then
  . "$ASDF_DIR/asdf.sh"
elif [ -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]; then
  . /opt/homebrew/opt/asdf/libexec/asdf.sh
else
set -euo pipefail

# Load asdf
if [ ! -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]; then
  echo "Error: /opt/homebrew/opt/asdf/libexec/asdf.sh not found" >&2
  exit 1
fi
. /opt/homebrew/opt/asdf/libexec/asdf.sh

# Navigate to backend directory
cd "$(dirname "$0")/backend" || exit 1

# Ensure gems are installed before deploying with Kamal
bundle check || bundle install
# Deploy with Kamal
bundle exec kamal deploy
