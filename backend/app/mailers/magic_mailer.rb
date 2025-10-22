class MagicMailer < ApplicationMailer
  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

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
    # For web client, use /client/ path
    # For web dashboard, use /login/verify
    # For macOS app, use custom URL scheme
    app_url = Rails.application.credentials.base_url || ENV.fetch('APP_URL', 'http://localhost:5000')
    app_url = "https://#{app_url}" unless app_url.start_with?('http')
    
    base_url = if web
      "#{app_url}/client/"
    elsif ENV["MAGIC_LINK_SCHEME"] == "remindly"
      "remindly://magic/verify"
    else
      "#{app_url}/magic/verify"
    end
    
    # Use URI to properly encode the token parameter
    uri = URI.parse(base_url)
    uri.query = URI.encode_www_form(token: token)
    uri.to_s
  end
end
