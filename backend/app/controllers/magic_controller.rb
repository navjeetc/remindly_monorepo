class MagicController < ApplicationController
  def request_link
    user  = User.find_or_create_by!(email: params.require(:email))
    token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
    
    # Detect if request is from voice web client (not the dashboard login)
    # Only /client/ requests should get web client links
    is_web_client = params[:client] == 'web' || (request.referer&.include?('/client') && !request.referer&.include?('/login'))
    
    # Debug logging
    Rails.logger.info "🔍 Magic link request:"
    Rails.logger.info "   Referer: #{request.referer}"
    Rails.logger.info "   Client param: #{params[:client]}"
    Rails.logger.info "   Is web client: #{is_web_client}"
    
    # Send magic link email
    MagicMailer.magic_link_email(user, token, web: is_web_client).deliver_now
    
    render json: { status: "sent" }
  end

  def verify
    token = params.require(:token)
    user  = User.find_signed(token, purpose: :magic_login)
    
    unless user
      # If it's a browser request, redirect to login with error
      if request.format.html?
        redirect_to login_path, alert: "Invalid or expired magic link. Please try again."
      else
        head :unauthorized
      end
      return
    end
    
    # If it's a browser request (HTML), set session and redirect to dashboard
    if request.format.html?
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
    render plain: issue_jwt(user:)
  end

  private
  def issue_jwt(user:) = JWT.encode({ uid: user.id, exp: 24.hours.from_now.to_i }, hmac_secret, "HS256")
  def hmac_secret = ENV.fetch("JWT_SECRET", "dev_secret_change_me")
end
