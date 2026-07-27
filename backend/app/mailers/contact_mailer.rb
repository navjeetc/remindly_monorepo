class ContactMailer < ApplicationMailer
  def contact_form_submission(name:, email:, description:)
    @name = name
    @email = email
    @description = description
    @submitted_at = Time.current

    admin_email = OFFICIAL_EMAIL

    mail(
      to: admin_email,
      subject: "New Contact Form Submission from #{name}",
      reply_to: email
    )
  end
end
