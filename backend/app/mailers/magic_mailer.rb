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
    # Voice clients go through the session login and land on /voice_reminders.
    # This used to point at /client/, the standalone JS client, which has been
    # retired — it was superseded by /voice_reminders and received no traffic.
    # /login/verify establishes the session that page needs; /magic/verify only
    # returns a JWT, which a browser cannot use on its own.
    app_url = origin_app_url(origin) || configured_app_url

    base_url = if web
      "#{app_url}/login/verify"
    elsif ENV["MAGIC_LINK_SCHEME"] == "remindly"
      "remindly://magic/verify"
    else
      "#{app_url}/magic/verify"
    end

    # Use URI to properly encode the token parameter
    uri = URI.parse(base_url)
    params = { token: token }
    # Send voice-client logins straight to the reminders page rather than the
    # caregiver dashboard. A senior following this link wants their reminders,
    # not a navigation step.
    params[:next] = "voice_reminders" if web
    uri.query = URI.encode_www_form(params)
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
