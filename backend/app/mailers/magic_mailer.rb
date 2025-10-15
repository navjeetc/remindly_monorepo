class MagicMailer < ApplicationMailer
  default from: ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def magic_link_email(user, token)
    @user = user
    @magic_link = generate_magic_link(token)
    
    mail(
      to: @user.email,
      subject: "Sign in to Remindly"
    )
  end

  private

  def generate_magic_link(token)
    # For macOS app, use custom URL scheme
    # For web, use HTTPS URL
    base_url = if ENV["MAGIC_LINK_SCHEME"] == "remindly"
      "remindly://magic/verify"
    else
      "#{ENV.fetch('APP_URL', 'http://localhost:5000')}/magic/verify"
    end
    
    # Use URI to properly encode the token parameter
    uri = URI.parse(base_url)
    uri.query = URI.encode_www_form(token: token)
    uri.to_s
  end
end
