#!/bin/bash

# Load asdf
if [ -n "$ASDF_DIR" ] && [ -f "$ASDF_DIR/asdf.sh" ]; then
  . "$ASDF_DIR/asdf.sh"
elif [ -f /opt/homebrew/opt/asdf/libexec/asdf.sh ]; then
  . /opt/homebrew/opt/asdf/libexec/asdf.sh
else
  echo "Error: Could not find asdf initialization script. Set ASDF_DIR or install asdf so deploy.sh can load the intended Ruby." >&2
  exit 1
fi

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Deploy with Kamal
bundle exec kamal deploy
