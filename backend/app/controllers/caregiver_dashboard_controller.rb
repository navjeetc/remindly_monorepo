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
      .includes(:reminder, :acknowledgements)

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
        acknowledgement: occ.acknowledgements.last ? {
          action: occ.acknowledgements.last.kind,
          acknowledged_at: occ.acknowledgements.last.created_at
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
      .includes(:reminder, :acknowledgements)

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
        acknowledgement: occ.acknowledgements.last ? {
          action: occ.acknowledgements.last.kind,
          acknowledged_at: occ.acknowledgements.last.created_at
        } : nil
      }
    }
  end

  # Get missed reminders count
  def missed_count
    count = Occurrence.joins(:reminder)
      .where(reminders: { user_id: @senior.id }, status: :missed)
      .where("scheduled_at >= ?", 7.days.ago)
      .count

    render json: { missed_count: count }
  end

  private

  # Everything in this controller is activity: what was announced, what was
  # marked done, what was missed. None of it may be shown for a care receiver
  # who has not yet agreed to any of this — a caregiver creating an account and
  # watching somebody's day before they have opened the link is the surveillance
  # case the whole design is built to prevent.
  #
  # The route refuses rather than the query happening to return nothing, which
  # is the difference between a guarantee and a coincidence: a provisional
  # account has no activity today, and would have some the moment anything ran.
  def set_senior
    senior_id = params.require(:senior_id)
    link = current_user.caregiver_links.find_by!(senior_id: senior_id)

    unless link.state_active?
      return render json: { error: "Not started yet" }, status: :forbidden
    end

    @senior = link.senior
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Access denied" }, status: :not_found
  end
end
