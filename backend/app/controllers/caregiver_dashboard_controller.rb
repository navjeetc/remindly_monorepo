class CaregiverDashboardController < ApplicationController
  before_action :authenticate!
  before_action :set_senior
  
  # Get senior's activity for the last 7 days
  def activity
    tz = ActiveSupport::TimeZone[@senior.tz]
    start_date = tz.now.beginning_of_day - 6.days
    end_date = tz.now.end_of_day
    
    occurrences = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, scheduled_at: start_date..end_date)
      .order(scheduled_at: :desc)
      .includes(:reminder, :acknowledgement)
    
    render json: occurrences.map { |occ|
      {
        id: occ.id,
        scheduled_at: occ.scheduled_at,
        status: occ.status,
        reminder: {
          id: occ.reminder.id,
          title: occ.reminder.title,
          notes: occ.reminder.notes,
          category: occ.reminder.category
        },
        acknowledgement: occ.acknowledgement ? {
          action: occ.acknowledgement.action,
          acknowledged_at: occ.acknowledgement.created_at
        } : nil
      }
    }
  end
  
  # Get today's reminders for a senior
  def today
    tz = ActiveSupport::TimeZone[@senior.tz]
    now = tz.now.beginning_of_day
    end_of_day = now.end_of_day
    
    occurrences = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, scheduled_at: now..end_of_day)
      .order(:scheduled_at)
      .includes(:reminder, :acknowledgement)
    
    render json: occurrences.map { |occ|
      {
        id: occ.id,
        scheduled_at: occ.scheduled_at,
        status: occ.status,
        reminder: {
          id: occ.reminder.id,
          title: occ.reminder.title,
          notes: occ.reminder.notes,
          category: occ.reminder.category
        },
        acknowledgement: occ.acknowledgement ? {
          action: occ.acknowledgement.action,
          acknowledged_at: occ.acknowledgement.created_at
        } : nil
      }
    }
  end
  
  # Get missed reminders count
  def missed_count
    count = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, status: :missed)
      .where('scheduled_at >= ?', 7.days.ago)
      .count
    
    render json: { missed_count: count }
  end
  
  private
  
  def set_senior
    senior_id = params.require(:senior_id)
    link = current_user.caregiver_links.find_by!(senior_id: senior_id)
    @senior = link.senior
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Senior not found or not linked" }, status: :not_found
  end
end
