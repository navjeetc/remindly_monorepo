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
        [feature_key, {
          name: config[:name],
          description: config[:description],
          enabled: enabled?(feature_key)
        }]
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
