class CoverageGapMailer < ApplicationMailer
  # Verified Postmark sender (see ReminderActivityMailer). notifications@remindly.app
  # is not a confirmed Sender Signature and was rejected on every send.
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

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

    mail(
      to: caregiver.email,
      subject: "Coverage Gap Alert for #{senior.display_name}"
    )
  end
end
