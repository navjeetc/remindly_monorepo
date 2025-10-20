class RemindersController < ApplicationController
  before_action :authenticate!
  before_action :set_reminder, only: %i[show update destroy]
  
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  def index
    reminders = current_user.reminders
    
    # Filter by category
    reminders = reminders.where(category: params[:category]) if params[:category].present?
    
    # Search by title or notes
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      reminders = reminders.where("title LIKE ? OR notes LIKE ?", search_term, search_term)
    end
    
    # Get total count BEFORE pagination (but AFTER filters)
    total_count = reminders.count
    
    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 100].min # Max 100 per page
    
    reminders = reminders.order(created_at: :desc)
                        .limit(per_page)
                        .offset((page - 1) * per_page)
    
    render json: {
      reminders: reminders,
      pagination: {
        page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count.to_f / per_page).ceil
      }
    }
  end

  def show
    render json: @reminder
  end

  def create
    r = current_user.reminders.create!(reminder_params)
    Recurrence.expand(r)
    render json: r, status: :created
  end

  def update
    @reminder.update!(reminder_params)
    
    # Regenerate occurrences when reminder is updated
    # Delete all pending occurrences to avoid duplicates
    # Keep only acknowledged occurrences for history
    @reminder.occurrences.where(status: :pending).destroy_all
    Recurrence.expand(@reminder)
    
    render json: @reminder
  end

  def destroy
    @reminder.destroy!
    head :no_content
  end

  def today
    tz  = ActiveSupport::TimeZone[current_user.tz]
    now = tz.now.beginning_of_day
    end_of_day = now.end_of_day
    
    ocs = Occurrence.joins(:reminder)
      .where(reminders: { user_id: current_user.id }, scheduled_at: now..end_of_day)
      .order(:scheduled_at)
    
    render json: ocs.as_json(include: { reminder: { only: %i[title notes category] } })
  end

  def bulk_destroy
    ids = params[:ids] || []
    deleted_count = current_user.reminders.where(id: ids).destroy_all.count
    
    render json: { 
      message: "Successfully deleted #{deleted_count} reminder(s)",
      deleted_count: deleted_count 
    }
  end

  private

  def set_reminder
    @reminder = current_user.reminders.find(params[:id])
  end

  def reminder_params = params.permit(:title, :notes, :rrule, :tz, :category, :start_time)
  
  def not_found
    render json: { error: "Reminder not found" }, status: :not_found
  end
  
  def unprocessable_entity(exception)
    render json: { 
      error: "Validation failed", 
      details: exception.record.errors.full_messages 
    }, status: :unprocessable_entity
  end
end
