# frozen_string_literal: true

class CoverageGapMailer < ApplicationMailer
  # Sender inherited from ApplicationMailer. This was one of the two mailers
  # that had already been given the correct address by hand; both now inherit
  # it, so there is a single definition rather than several that happen to
  # agree.

  # Send coverage gap notification email
  # @param caregiver [User] The caregiver to notify
  # @param senior [User] The senior with coverage gaps
  # @param gaps [Array<Date>] Array of dates with no coverage
  def notify_gap(caregiver:, senior:, gaps:)
    @caregiver = caregiver
    @senior = senior
    @gaps = gaps
    @coverage_url = senior_coverage_url(senior)
    @availability_url = caregiver_availabilities_url
    @settings_url = profile_url

    mail(
      to: caregiver.email,
      subject: "Coverage Gap Alert for #{senior.display_name}"
    )
  end
end
