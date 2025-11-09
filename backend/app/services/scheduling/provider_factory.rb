module Scheduling
  class ProviderFactory
    # Create a provider instance based on the integration
    # @param integration [SchedulingIntegration] The integration record
    # @return [BaseProvider] Provider instance
    def self.create(integration)
      case integration.provider
      when "acuity"
        AcuityProvider.new(integration)
      when "calendly"
        # CalendlyProvider.new(integration) # Future implementation
        raise NotImplementedError, "Calendly provider not yet implemented"
      else
        raise ArgumentError, "Unknown provider: #{integration.provider}"
      end
    end

    # Verify credentials for a provider without creating an integration
    # @param provider [String] Provider name ('acuity', 'calendly')
    # @param credentials [Hash] Credentials hash
    # @return [Boolean] True if credentials are valid
    def self.verify_credentials(provider, credentials)
      case provider
      when "acuity"
        verify_acuity_credentials(credentials)
      when "calendly"
        # verify_calendly_credentials(credentials) # Future implementation
        raise NotImplementedError, "Calendly provider not yet implemented"
      else
        raise ArgumentError, "Unknown provider: #{provider}"
      end
    end

    private

    def self.verify_acuity_credentials(credentials)
      user_id = credentials[:provider_user_id]
      api_key = credentials[:api_key]

      return false if user_id.blank? || api_key.blank?

      # Create a temporary integration object for verification
      temp_integration = SchedulingIntegration.new(
        provider: :acuity,
        provider_user_id: user_id,
        api_key: api_key,
        status: :inactive
      )

      provider = AcuityProvider.new(temp_integration)
      provider.verify_credentials
    rescue => e
      Rails.logger.error "Credential verification failed: #{e.message}"
      false
    end
  end
end
