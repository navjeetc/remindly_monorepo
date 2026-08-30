# frozen_string_literal: true

# Reads the aggregate public-page tally. See PageCount for what it contains.
#
# The question this page exists to answer is "did that post send anyone", so the
# referrer table is the point and everything else is context.
class Admin::TrafficController < WebController
  before_action :authenticate!
  before_action :require_admin!
  layout "dashboard"

  DEFAULT_DAYS = 30
  MAX_DAYS = 365

  def index
    @days = clamped_days
    @since = @days.days.ago.to_date
    counts = PageCount.since(@since)

    @human_views = counts.humans.sum(:count)
    @bot_views = counts.bots.sum(:count)
    @referred_views = counts.humans.referred.sum(:count)

    @by_referrer = totals_for(counts.humans.referred, :referrer_host)
    @by_source = totals_for(counts.humans.tagged, :source)
    @by_path = totals_for(counts.humans, :path)

    # Daily, so a spike on the day something was posted is visible at a glance —
    # which is the shape the answer usually takes.
    @by_day = counts.humans.group(:day).sum(:count).sort_by { |day, _| day }.reverse.first(14)
  end

  private

  def totals_for(scope, column)
    scope.group(column).sum(:count).sort_by { |_, total| -total }.first(15)
  end

  def clamped_days
    days = params[:days].to_i
    return DEFAULT_DAYS if days <= 0

    days.clamp(1, MAX_DAYS)
  end

  def require_admin!
    unless current_user&.role_admin?
      redirect_to dashboard_path, alert: "Access denied. Admin privileges required."
    end
  end
end
