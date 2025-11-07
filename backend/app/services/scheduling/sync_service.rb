module Scheduling
  class SyncService
    attr_reader :integration

    def initialize(integration)
      @integration = integration
    end

    # Sync all appointments from the integration
    # @param start_date [Date] Start date for sync (default: 7 days ago)
    # @param end_date [Date] End date for sync (default: 90 days from now)
    # @return [Hash] Sync results
    def sync_appointments(start_date: 7.days.ago.to_date, end_date: 90.days.from_now.to_date)
      return { success: false, error: "Integration not active" } unless integration.status_active?

      provider = ProviderFactory.create(integration)
      appointments = provider.fetch_appointments(start_date, end_date)

      results = {
        success: true,
        total: appointments.count,
        created: 0,
        updated: 0,
        errors: []
      }

      appointments.each do |appointment|
        begin
          sync_appointment(appointment)
          
          # Check if task was created or updated
          task = Task.find_by(external_source: integration.provider, external_id: appointment[:id])
          if task.created_at > 5.seconds.ago
            results[:created] += 1
          else
            results[:updated] += 1
          end
        rescue => e
          Rails.logger.error "Failed to sync appointment #{appointment[:id]}: #{e.message}"
          results[:errors] << { appointment_id: appointment[:id], error: e.message }
        end
      end

      integration.mark_synced!
      integration.mark_active!

      results
    rescue => e
      Rails.logger.error "Sync failed for integration #{integration.id}: #{e.message}"
      integration.mark_error!(e.message)
      { success: false, error: e.message }
    end

    # Sync a single appointment
    # @param appointment [Hash] Appointment data
    # @return [Task] Created or updated task
    def sync_appointment(appointment)
      task = Task.find_or_initialize_by(
        external_source: integration.provider,
        external_id: appointment[:id]
      )

      # Determine if this is a new task
      is_new = task.new_record?

      task.assign_attributes(
        senior_id: integration.senior_id,
        title: appointment[:title] || "#{appointment[:type]} Appointment",
        description: appointment[:notes],
        task_type: :appointment,
        status: map_external_status(appointment[:status]),
        priority: :medium,
        scheduled_at: appointment[:datetime],
        duration_minutes: appointment[:duration],
        location: appointment[:location],
        notes: build_notes(appointment),
        created_by: integration.user,
        scheduling_integration: integration,
        external_url: appointment[:calendar_url],
        sync_metadata: appointment[:raw_data]
      )

      # Only set assigned_to if it's a new task and senior has caregivers
      if is_new && integration.senior.present?
        # Assign to the integration creator by default
        task.assigned_to = integration.user
      end

      task.save!
      task
    end

    # Sync a single appointment by external ID
    # @param external_id [String] External appointment ID
    # @return [Task] Updated task
    def sync_appointment_by_id(external_id)
      provider = ProviderFactory.create(integration)
      appointment = provider.get_appointment(external_id)
      
      return nil unless appointment

      sync_appointment(appointment)
    end

    private

    def map_external_status(external_status)
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

    def build_notes(appointment)
      notes = []
      notes << "Synced from #{integration.provider.titleize}"
      notes << "Client: #{appointment[:client_name]}" if appointment[:client_name].present?
      notes << "Email: #{appointment[:client_email]}" if appointment[:client_email].present?
      notes << "Phone: #{appointment[:client_phone]}" if appointment[:client_phone].present?
      notes << "\n#{appointment[:notes]}" if appointment[:notes].present?
      notes.join("\n")
    end
  end
end
