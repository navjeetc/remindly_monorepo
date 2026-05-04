class MagicMailer < ApplicationMailer
  ALLOWED_ORIGIN_HOSTS = %w[remindly.anakhsoft.com remindly.care www.remindly.care localhost 127.0.0.1].freeze

  default from: Rails.application.credentials.admin_email || ENV.fetch("MAILER_FROM", "noreply@remindly.app")

  def magic_link_email(user, token, web: false, origin: nil)
    @user = user
    @magic_link = generate_magic_link(token, web: web, origin: origin)

    mail(
      to: @user.email,
      subject: "Sign in to Remindly"
    )
  end

  private

  def generate_magic_link(token, web: false, origin: nil)
    # For web client (voice announcements), use /client/ path
    # For API/macOS app, use /magic/verify or custom URL scheme
    app_url = origin_app_url(origin) || configured_app_url

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

  # Use the origin the user actually started from when it's an allowed host,
  # so a login begun on remindly.care doesn't email a remindly.anakhsoft.com link.
  def origin_app_url(origin)
    return nil if origin.blank?
    uri = URI.parse(origin)
    return nil unless uri.host && ALLOWED_ORIGIN_HOSTS.include?(uri.host)
    "#{uri.scheme}://#{uri.host}#{uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ''}"
  rescue URI::InvalidURIError
    nil
  end

  def configured_app_url
    app_url = Rails.application.credentials.base_url || ENV.fetch('APP_URL', 'http://localhost:5000')
    app_url.start_with?('http') ? app_url : "https://#{app_url}"
  end
end
