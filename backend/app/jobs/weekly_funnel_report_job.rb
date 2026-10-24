# frozen_string_literal: true

# Sends FunnelReportMailer.weekly on Monday mornings; see config/recurring.yml.
class WeeklyFunnelReportJob < ApplicationJob
  queue_as :default

  def perform
    FunnelReportMailer.weekly.deliver_now
  end
end
