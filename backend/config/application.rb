require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Spanish exists here only so the telephone can speak it — the dashboard is
    # English throughout. Declared because enforce_available_locales rejects any
    # locale not on this list, and the call script is looked up with an explicit
    # locale: rather than by switching I18n.locale globally.
    config.i18n.available_locales = [ :en, :es ]
    config.i18n.default_locale = :en

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Every deliver_later runs through our own subclass so that a permanently
    # refused address is discarded rather than retried — see MailDeliveryJob.
    #
    # Set here rather than per-environment so the test suite exercises the same
    # job production uses. Note the warning in production.rb: this setting must
    # never be nil, which makes every deliver_later raise and silently sends no
    # queued mail at all. A named subclass of ActionMailer::MailDeliveryJob is
    # safe; an empty value is not.
    config.action_mailer.delivery_job = "MailDeliveryJob"

    # Support both HTML dashboard views and JSON API endpoints.
    config.api_only = false
  end
end
