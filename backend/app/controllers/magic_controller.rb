class MagicController < ApplicationController
  def request_link
    user  = User.find_or_create_by!(email: params.require(:email))
    token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)

    # Detect if request is from voice web client (not the dashboard login)
    # Use explicit client parameter to avoid fragile referer-based detection
    is_web_client = params[:client] == "web"

    # Send magic link email
    MagicMailer.magic_link_email(user, token, web: is_web_client, origin: request.base_url).deliver_now

    render json: { status: "sent" }
  end

  def verify
    # Support both GET (email links) and POST (API) for token verification
    # POST is preferred for security (token not in URL/logs)
    # Rails automatically parses JSON request bodies into params
    token = params[:token]

    return head :bad_request if token.blank?

    user = User.find_signed(token, purpose: :magic_login)

    unless user
      # Track failed login attempt
      ahoy.track "Login Failed", {
        reason: "invalid_or_expired_token",
        method: "magic_link",
        ip: request.remote_ip,
        user_agent: request.user_agent
      }

      # If it's a browser request, redirect to login with error
      if request.format.html?
        # Keep the "for my parent" start: without it the new link is a plain
        # one, and the account it creates is asked the role question after all.
        redirect_to login_path(for: ("parent" if params[:for] == "parent")),
          alert: "That sign-in link has expired or isn't valid. Enter your email below for a new one."
      else
        head :unauthorized
      end
      return
    end

    # Authenticate user with Ahoy
    ahoy.authenticate(user)

    # Track successful login
    ahoy.track "Login Success", {
      method: "magic_link",
      client_type: request.format.html? ? "web" : "api",
      ip: request.remote_ip,
      user_agent: request.user_agent
    }

    # If it's a browser request (HTML), set session and redirect to dashboard
    if request.format.html?
      # A link requested from "Set up reminders for my parent" has already said
      # what this account is for, so a new one skips the role question. Only
      # ever a first choice: choose_role_once refuses to change a role that is
      # set, so an existing account keeps whatever it is.
      user.choose_role_once("caregiver") if params[:for] == "parent"

      payload = { uid: user.id, exp: 30.days.from_now.to_i }
      jwt_token = JWT.encode(payload, hmac_secret, "HS256")
      session[:jwt_token] = jwt_token
      redirect_to dashboard_path, notice: "Successfully signed in as #{user.display_name}"
    else
      # For API requests, return JWT token
      render plain: issue_jwt(user:)
    end
  end

  def dev_exchange
    return head :forbidden unless Rails.env.development?
    user = User.find_or_create_by!(email: params.require(:email))

    # Authenticate user with Ahoy
    ahoy.authenticate(user)

    # Track dev login
    ahoy.track "Login Success", {
      method: "dev_exchange",
      client_type: "api",
      ip: request.remote_ip,
      user_agent: request.user_agent
    }

    render plain: issue_jwt(user:)
  end

  private
  def issue_jwt(user:) = JWT.encode({ uid: user.id, exp: 24.hours.from_now.to_i }, hmac_secret, "HS256")
  def hmac_secret = ENV.fetch("JWT_SECRET", "dev_secret_change_me")
end
