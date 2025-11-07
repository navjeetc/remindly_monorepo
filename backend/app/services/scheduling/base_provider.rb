module Scheduling
  class BaseProvider
    attr_reader :integration

    def initialize(integration)
      @integration = integration
    end

    # Fetch appointments from external system
    # @param start_date [Date] Start date for fetching appointments
    # @param end_date [Date] End date for fetching appointments
    # @return [Array<Hash>] Array of appointment hashes
    def fetch_appointments(start_date, end_date)
      raise NotImplementedError, "#{self.class} must implement #fetch_appointments"
    end

    # Get a single appointment by external ID
    # @param external_id [String] External appointment ID
    # @return [Hash] Appointment data
    def get_appointment(external_id)
      raise NotImplementedError, "#{self.class} must implement #get_appointment"
    end

    # Create an appointment in external system
    # @param params [Hash] Appointment parameters
    # @return [Hash] Created appointment data
    def create_appointment(params)
      raise NotImplementedError, "#{self.class} must implement #create_appointment"
    end

    # Update an appointment in external system
    # @param external_id [String] External appointment ID
    # @param params [Hash] Updated appointment parameters
    # @return [Hash] Updated appointment data
    def update_appointment(external_id, params)
      raise NotImplementedError, "#{self.class} must implement #update_appointment"
    end

    # Cancel an appointment in external system
    # @param external_id [String] External appointment ID
    # @return [Boolean] Success status
    def cancel_appointment(external_id)
      raise NotImplementedError, "#{self.class} must implement #cancel_appointment"
    end

    # Get available appointment types from external system
    # @return [Array<Hash>] Array of appointment type hashes
    def get_appointment_types
      raise NotImplementedError, "#{self.class} must implement #get_appointment_types"
    end

    # Verify credentials are valid
    # @return [Boolean] True if credentials are valid
    def verify_credentials
      raise NotImplementedError, "#{self.class} must implement #verify_credentials"
    end

    protected

    # Parse appointment data into standardized format
    # @param raw_data [Hash] Raw appointment data from provider
    # @return [Hash] Standardized appointment hash
    def parse_appointment(raw_data)
      {
        id: raw_data[:id],
        title: raw_data[:title] || raw_data[:type],
        type: raw_data[:type],
        datetime: raw_data[:datetime],
        duration: raw_data[:duration],
        location: raw_data[:location],
        notes: raw_data[:notes],
        status: raw_data[:status],
        client_name: raw_data[:client_name],
        client_email: raw_data[:client_email],
        client_phone: raw_data[:client_phone],
        calendar_url: raw_data[:calendar_url],
        raw_data: raw_data
      }
    end

    # Map external status to internal task status
    # @param external_status [String] Status from external system
    # @return [Symbol] Internal task status
    def map_status(external_status)
      case external_status&.downcase
      when 'scheduled', 'confirmed', 'booked'
        :assigned
      when 'completed', 'done'
        :completed
      when 'canceled', 'cancelled'
        :cancelled
      when 'no-show', 'missed'
        :cancelled
      else
        :pending
      end
    end
  end
end
