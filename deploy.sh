#!/bin/bash
set -euo pipefail

# Load asdf
if [ -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]; then
  . /opt/homebrew/opt/asdf/libexec/asdf.sh
else
  echo "Error: asdf not found at /opt/homebrew/opt/asdf/libexec/asdf.sh" >&2
  exit 1
fi

# Navigate to backend directory
cd "$(dirname "$0")/backend" || exit 1

# Ensure gems are installed before deploying with Kamal
bundle check || bundle install

# Deploy with Kamal
bundle exec kamal deploy
