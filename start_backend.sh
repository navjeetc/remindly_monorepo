#!/bin/bash

# Load asdf
. /opt/homebrew/opt/asdf/libexec/asdf.sh

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Install gems if needed
bundle check || bundle install

# Start Rails server
# Rails binds to localhost by default, so a phone or tablet on the LAN cannot
# reach this no matter what config.hosts allows. Set BIND=0.0.0.0 to test the
# voice client on a real device (its unlock path is iOS-only), or use
# `make backend-up-lan`, which prints the LAN URL for you.
BIND="${BIND:-127.0.0.1}"
JWT_SECRET=please_change_me bundle exec rails s -p 5000 -b "$BIND"
