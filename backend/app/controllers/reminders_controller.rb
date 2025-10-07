class RemindersController < ApplicationController
  before_action :authenticate!
  before_action :set_reminder, only: %i[show update destroy]

  def index
    reminders = current_user.reminders.order(created_at: :desc)
    render json: reminders
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
    ocs = Occurrence.joins(:reminder)
      .where(reminders: { user_id: current_user.id }, scheduled_at: now..now.end_of_day)
      .order(:scheduled_at)
    render json: ocs.as_json(include: { reminder: { only: %i[title notes category] } })
  end

  private

  def set_reminder
    @reminder = current_user.reminders.find(params[:id])
  end

  def reminder_params = params.permit(:title, :notes, :rrule, :tz, :category)
end
