module Api
  class CaregiverAvailabilitiesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_availability, only: [:update, :destroy]

    # GET /api/availability
    def index
      @availabilities = CaregiverAvailability.all

      # Filter by caregiver
      if params[:caregiver_id].present?
        @availabilities = @availabilities.for_caregiver(params[:caregiver_id])
      end

      # Filter by date
      if params[:date].present?
        @availabilities = @availabilities.for_date(params[:date])
      end

      # Filter by date range
      if params[:start_date].present? && params[:end_date].present?
        @availabilities = @availabilities.in_date_range(params[:start_date], params[:end_date])
      end

      # If senior_id is provided, get availability for all caregivers of that senior
      if params[:senior_id].present?
        senior = User.find(params[:senior_id])
        caregiver_ids = senior.caregivers.pluck(:id)
        @availabilities = @availabilities.where(caregiver_id: caregiver_ids)
      end

      @availabilities = @availabilities.order(:date, :start_time)

      render json: @availabilities.as_json(include: {
        caregiver: { only: [:id, :email, :name] }
      })
    end

    # POST /api/availability
    def create
      @availability = current_user.caregiver_availabilities.build(availability_params)

      if @availability.save
        render json: @availability, status: :created
      else
        render json: { errors: @availability.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /api/availability/:id
    def update
      if @availability.update(availability_params)
        render json: @availability
      else
        render json: { errors: @availability.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /api/availability/:id
    def destroy
      @availability.destroy
      head :no_content
    end

    private

    def set_availability
      @availability = current_user.caregiver_availabilities.find(params[:id])
    end

    def availability_params
      params.require(:availability).permit(:date, :start_time, :end_time, :notes)
    end
  end
end
