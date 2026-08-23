# Feature flag system for enabling/disabling features
class FeatureFlag
  # Define available features
  FEATURES = {
    native_scheduling: {
      name: "Native Scheduling",
      description: "Built-in appointment scheduling without external services",
      default: false,
      env_var: "ENABLE_NATIVE_SCHEDULING"
    },
    external_scheduling: {
      name: "External Scheduling Integrations",
      description: "Connect to external scheduling services (Acuity, Calendly)",
      default: true,
      env_var: "ENABLE_EXTERNAL_SCHEDULING"
    },
    # The outer of two locks on reminder phone calls. This one says the code may
    # run at all; a senior's own voice_reminders_enabled and phone say whether it
    # runs for them.
    #
    # It exists because the inner lock is two ordinary columns, and the only way
    # to try this in production is to set them — after which calls begin within
    # the minute, and the only way to stop them is a deploy. This flag is a lever
    # that can be thrown without one, and turning the feature on becomes a
    # reviewed change to the deploy configuration rather than a console update.
    phone_call_reminders: {
      name: "Phone Call Reminders",
      description: "Deliver reminders as an outbound phone call, acknowledged by keypad",
      default: false,
      env_var: "ENABLE_PHONE_CALL_REMINDERS"
    }
  }.freeze

  class << self
    # Check if a feature is enabled
    # @param feature [Symbol] Feature key
    # @return [Boolean] True if feature is enabled
    def enabled?(feature)
      return false unless FEATURES.key?(feature)

      feature_config = FEATURES[feature]

      # Check environment variable first
      env_value = ENV[feature_config[:env_var]]
      return env_value == "true" if env_value.present?

      # Fall back to default
      feature_config[:default]
    end

    # Check if a feature is disabled
    # @param feature [Symbol] Feature key
    # @return [Boolean] True if feature is disabled
    def disabled?(feature)
      !enabled?(feature)
    end

    # Get all features with their status
    # @return [Hash] Features with enabled status
    def all
      FEATURES.map do |feature_key, config|
        [ feature_key, {
          name: config[:name],
          description: config[:description],
          enabled: enabled?(feature_key)
        } ]
      end.to_h
    end

    # Enable a feature (for testing)
    # @param feature [Symbol] Feature key
    def enable!(feature)
      return unless FEATURES.key?(feature)
      ENV[FEATURES[feature][:env_var]] = "true"
    end

    # Disable a feature (for testing)
    # @param feature [Symbol] Feature key
    def disable!(feature)
      return unless FEATURES.key?(feature)
      ENV[FEATURES[feature][:env_var]] = "false"
    end
  end
end
