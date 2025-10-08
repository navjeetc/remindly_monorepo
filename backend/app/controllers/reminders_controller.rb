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
    Rails.logger.info "📝 Update params: #{reminder_params.inspect}"
    Rails.logger.info "📝 Category param: '#{params[:category]}' (class: #{params[:category].class})"
    @reminder.update!(reminder_params)
    Rails.logger.info "📝 Reminder category after update: '#{@reminder.category}' (integer: #{@reminder.category_before_type_cast})"
    # Regenerate occurrences when reminder is updated
    # Delete all pending occurrences (past and future) to avoid duplicates
    # Keep only acknowledged occurrences for history
    deleted_count = @reminder.occurrences.where(status: :pending).destroy_all.count
    Rails.logger.info "🗑️ Deleted #{deleted_count} pending occurrences for reminder #{@reminder.id}"
    Recurrence.expand(@reminder)
    new_count = @reminder.occurrences.reload.count
    Rails.logger.info "✅ Created new occurrences, total count: #{new_count}"
    Rails.logger.info "📋 Occurrences: #{@reminder.occurrences.inspect}"
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
    Rails.logger.info "📅 Fetching today's occurrences for user #{current_user.id}"
    Rails.logger.info "🕐 Timezone: #{tz}, Range: #{now} to #{end_of_day}"
    ocs = Occurrence.joins(:reminder)
      .where(reminders: { user_id: current_user.id }, scheduled_at: now..end_of_day)
      .order(:scheduled_at)
    Rails.logger.info "✅ Found #{ocs.count} occurrences for today"
    ocs.each { |oc| Rails.logger.info "  - #{oc.id}: #{oc.scheduled_at} (#{oc.status})" }
    render json: ocs.as_json(include: { reminder: { only: %i[title notes category] } })
  end

  private

  def set_reminder
    @reminder = current_user.reminders.find(params[:id])
  end

  def reminder_params = params.permit(:title, :notes, :rrule, :tz, :category, :start_time)
end
