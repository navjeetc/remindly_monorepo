#!/bin/bash

# Load asdf
. /opt/homebrew/opt/asdf/libexec/asdf.sh

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Deploy with Kamal
bundle exec kamal deploy
