# Load version from VERSION file at the root of the monorepo
VERSION_FILE = Rails.root.join('../../VERSION')

if File.exist?(VERSION_FILE)
  APP_VERSION = File.read(VERSION_FILE).strip
else
  # Fallback for production where VERSION file might not be accessible
  APP_VERSION = ENV.fetch('APP_VERSION', '0.2.2')
end
