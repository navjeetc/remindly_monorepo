class MagicMailer < ApplicationMailer
  default from: ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def magic_link_email(user, token, web: false)
    @user = user
    @magic_link = generate_magic_link(token, web: web)
    
    mail(
      to: @user.email,
      subject: "Sign in to Remindly"
    )
  end

  private

  def generate_magic_link(token, web: false)
    # For web dashboard, always use web URL
    # For macOS app, use custom URL scheme
    base_url = if web
      "#{ENV.fetch('APP_URL', 'http://localhost:5000')}/login/verify"
    elsif ENV["MAGIC_LINK_SCHEME"] == "remindly"
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
