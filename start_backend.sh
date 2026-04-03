#!/bin/bash

# Load asdf
. /opt/homebrew/opt/asdf/libexec/asdf.sh

# Navigate to backend directory
cd "$(dirname "$0")/backend"

# Install gems if needed
bundle check || bundle install

# Start Rails server
JWT_SECRET=please_change_me bundle exec rails s -p 5000
