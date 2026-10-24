# frozen_string_literal: true

# The Monday email that says what last week's links and ads brought: page views
# by where they came from, clicks on the setup-call offer, and the activation
# funnel by ?from= tag. The same numbers as Admin -> Traffic, sent so the ad
# test is read every week without anybody remembering to open that page.
#
# Aggregates only, as on that page: nothing here names a visitor, and the
# accounts are counted, never listed.
class FunnelReportMailer < ApplicationMailer
  DAYS = 7

  def weekly(since: DAYS.days.ago.to_date)
    @since = since
    @until = Date.current
    counts = PageCount.since(@since).humans

    @human_views = counts.sum(:count)
    @referred_views = counts.referred.sum(:count)
    @setup_call_clicks = counts.where(path: "/setup-call").sum(:count)
    @by_referrer = top(counts.referred, :referrer_host)
    @by_source = top(counts.tagged, :source)

    activation = Activation.new(since: @since)
    @totals = activation.totals
    @by_activation_source = activation.by_source

    mail(to: ApplicationMailer.admin_recipient,
         subject: "Remindly last week: #{@totals[:created]} sign-ups, #{@referred_views} visits from other sites")
  end

  private

  def top(scope, column)
    scope.group(column).sum(:count).sort_by { |_, total| -total }.first(10)
  end
end
