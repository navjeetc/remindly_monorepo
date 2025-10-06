class RemindersController < ApplicationController
  before_action :authenticate!

  def create
    r = current_user.reminders.create!(reminder_params)
    Recurrence.expand(r)
    render json: r, status: :created
  end

  def today
    tz  = ActiveSupport::TimeZone[current_user.tz]
    now = tz.now.beginning_of_day
    ocs = Occurrence.joins(:reminder)
      .where(reminders: { user_id: current_user.id }, scheduled_at: now..now.end_of_day)
      .order(:scheduled_at)
    render json: ocs.as_json(include: { reminder: { only: %i[title notes category] } })
  end

  private
  def reminder_params = params.permit(:title, :notes, :rrule, :tz, :category)
end
