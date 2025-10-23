class Ahoy::Store < Ahoy::DatabaseStore
end

# set to true for JavaScript tracking
Ahoy.api = false

# Since we have both API and web controllers, we'll handle visit tracking manually
# This prevents automatic visit creation on every API request
Ahoy.api_only = false

# Track bots in development for testing, exclude in production
Ahoy.track_bots = Rails.env.development?

# set to true for geocoding (and add the geocoder gem to your Gemfile)
# we recommend configuring local geocoding as well
# see https://github.com/ankane/ahoy#geocoding
Ahoy.geocode = false

# Visit duration - create new visit after 4 hours of inactivity
Ahoy.visit_duration = 4.hours

# Visitor duration - create new visitor token after 2 years
Ahoy.visitor_duration = 2.years
