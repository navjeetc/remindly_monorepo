class ContactMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def contact_form_submission(name:, email:, description:)
    @name = name
    @email = email
    @description = description
    @submitted_at = Time.current
    
    admin_email = Rails.application.credentials.admin_email || ENV.fetch("ADMIN_EMAIL", "admin@remindly.app")
    
    mail(
      to: admin_email,
      subject: "New Contact Form Submission from #{name}",
      reply_to: email
    )
  end
end
