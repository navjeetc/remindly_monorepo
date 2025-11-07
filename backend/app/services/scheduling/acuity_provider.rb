require 'net/http'
require 'json'

module Scheduling
  class AcuityProvider < BaseProvider
    BASE_URL = "https://acuityscheduling.com/api/v1"

    def fetch_appointments(start_date, end_date)
      response = get("/appointments", {
        minDate: start_date.iso8601,
        maxDate: end_date.iso8601
      })

      return [] unless response.is_a?(Array)

      response.map { |appt| parse_acuity_appointment(appt) }
    rescue => e
      Rails.logger.error "Acuity fetch_appointments error: #{e.message}"
      integration.mark_error!("Failed to fetch appointments: #{e.message}")
      []
    end

    def get_appointment(external_id)
      response = get("/appointments/#{external_id}")
      parse_acuity_appointment(response)
    rescue => e
      Rails.logger.error "Acuity get_appointment error: #{e.message}"
      nil
    end

    def create_appointment(params)
      response = post("/appointments", {
        appointmentTypeID: params[:appointment_type_id],
        datetime: params[:datetime].iso8601,
        firstName: params[:client][:firstName],
        lastName: params[:client][:lastName],
        email: params[:client][:email],
        phone: params[:client][:phone],
        notes: params[:notes]
      })

      parse_acuity_appointment(response)
    rescue => e
      Rails.logger.error "Acuity create_appointment error: #{e.message}"
      integration.mark_error!("Failed to create appointment: #{e.message}")
      nil
    end

    def update_appointment(external_id, params)
      response = put("/appointments/#{external_id}", {
        datetime: params[:datetime]&.iso8601,
        notes: params[:notes]
      }.compact)

      parse_acuity_appointment(response)
    rescue => e
      Rails.logger.error "Acuity update_appointment error: #{e.message}"
      nil
    end

    def cancel_appointment(external_id)
      put("/appointments/#{external_id}/cancel")
      true
    rescue => e
      Rails.logger.error "Acuity cancel_appointment error: #{e.message}"
      false
    end

    def get_appointment_types
      response = get("/appointment-types")
      return [] unless response.is_a?(Array)

      response.map do |type|
        {
          id: type['id'],
          name: type['name'],
          duration: type['duration'],
          description: type['description']
        }
      end
    rescue => e
      Rails.logger.error "Acuity get_appointment_types error: #{e.message}"
      []
    end

    def verify_credentials
      response = get("/me")
      response.is_a?(Hash) && response['id'].present?
    rescue => e
      Rails.logger.error "Acuity verify_credentials error: #{e.message}"
      false
    end

    private

    def parse_acuity_appointment(data)
      return nil unless data.is_a?(Hash)

      {
        id: data['id'].to_s,
        title: data['type'] || 'Appointment',
        type: data['type'],
        datetime: Time.zone.parse(data['datetime']),
        duration: data['duration'].to_i,
        location: parse_location(data),
        notes: data['notes'],
        status: data['canceled'] ? 'canceled' : 'scheduled',
        client_name: "#{data['firstName']} #{data['lastName']}".strip,
        client_email: data['email'],
        client_phone: data['phone'],
        calendar_url: data['confirmationPage'],
        raw_data: data
      }
    end

    def parse_location(data)
      if data['location'].present?
        data['location']
      elsif data['calendar'].present?
        data['calendar']
      else
        'Not specified'
      end
    end

    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      add_auth_headers(request)

      response = execute_request(uri, request)
      JSON.parse(response.body)
    end

    def post(path, body = {})
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/json'
      add_auth_headers(request)
      request.body = body.to_json

      response = execute_request(uri, request)
      JSON.parse(response.body)
    end

    def put(path, body = {})
      uri = URI("#{BASE_URL}#{path}")
      request = Net::HTTP::Put.new(uri)
      request['Content-Type'] = 'application/json'
      add_auth_headers(request)
      request.body = body.to_json if body.any?

      response = execute_request(uri, request)
      response.body.present? ? JSON.parse(response.body) : {}
    end

    def add_auth_headers(request)
      # Acuity uses HTTP Basic Auth with user_id and api_key
      request.basic_auth(integration.provider_user_id, integration.api_key)
    end

    def execute_request(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "HTTP #{response.code}: #{response.body}"
        end

        response
      end
    end
  end
end
