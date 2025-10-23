# Load version from VERSION file
# Priority order:
# 1. Monorepo root VERSION file (../../VERSION)
# 2. Rails root VERSION file (./VERSION) - for production deployments
# 3. APP_VERSION environment variable
# 4. Fallback with error in production

RAILS_ROOT_VERSION_FILE = Rails.root.join('VERSION')
MONOREPO_ROOT_VERSION_FILE = Rails.root.join('../../VERSION')

if File.exist?(MONOREPO_ROOT_VERSION_FILE)
  APP_VERSION = File.read(MONOREPO_ROOT_VERSION_FILE).strip
elsif File.exist?(RAILS_ROOT_VERSION_FILE)
  APP_VERSION = File.read(RAILS_ROOT_VERSION_FILE).strip
elsif ENV['APP_VERSION']
  APP_VERSION = ENV['APP_VERSION']
else
  # Fallback if no VERSION file or ENV variable is available
  # This should be documented in deployment instructions
  if Rails.env.production?
    raise "APP_VERSION not configured! Set APP_VERSION environment variable in deploy.yml"
  else
    APP_VERSION = '0.0.0-missing'
  end
end
