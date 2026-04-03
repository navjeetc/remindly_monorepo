class CaregiverInvitationMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def invitation_email(caregiver:, senior:, inviter:)
    @caregiver = caregiver
    @senior = senior
    @inviter = inviter
    @login_url = generate_login_url
    
    mail(
      to: @caregiver.email,
      subject: "You've been invited to help care for #{@senior.display_name}"
    )
  end

  private

  def generate_login_url
    app_url = Rails.application.credentials.base_url || ENV.fetch('APP_URL', 'http://localhost:5000')
    app_url = "https://#{app_url}" unless app_url.start_with?('http')
    "#{app_url}/login"
  end
end
