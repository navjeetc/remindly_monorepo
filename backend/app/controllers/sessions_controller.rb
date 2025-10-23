class SessionsController < ActionController::Base
  layout false
  skip_before_action :verify_authenticity_token, only: [:verify_magic_link]
  
  def new
    # Show login page
  end
  
  # Request magic link via email
  def request_magic_link
    email = params[:email]
    user = User.find_or_create_by!(email: email)
    token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
    
    # Send magic link email (web: false for dashboard, goes to /magic/verify)
    MagicMailer.magic_link_email(user, token, web: false).deliver_now
    
    redirect_to login_path, notice: "Magic link sent! Check your email to sign in."
  end
  
  # Verify magic link and log in
  def verify_magic_link
    token = params[:token]
    user = User.find_signed(token, purpose: :magic_login)
    
    if user
      # Authenticate user with Ahoy
      ahoy.authenticate(user)
      
      # Track successful login
      ahoy.track "Login Success", {
        method: "magic_link_web",
        client_type: "web_dashboard",
        ip: request.remote_ip,
        user_agent: request.user_agent
      }
      
      # Generate JWT and store in session
      payload = { uid: user.id, exp: 30.days.from_now.to_i }
      jwt_token = JWT.encode(payload, hmac_secret, "HS256")
      session[:jwt_token] = jwt_token
      
      # Redirect to profile if name is not set
      if user.name.blank?
        redirect_to profile_path, notice: "Welcome! Please complete your profile to continue."
      else
        redirect_to dashboard_path, notice: "Successfully signed in as #{user.display_name}"
      end
    else
      # Track failed login
      ahoy.track "Login Failed", {
        reason: "invalid_or_expired_token",
        method: "magic_link_web",
        client_type: "web_dashboard",
        ip: request.remote_ip,
        user_agent: request.user_agent
      }
      
      redirect_to login_path, alert: "Invalid or expired magic link. Please try again."
    end
  end
  
  # Dev mode quick login
  def dev_login
    unless Rails.env.development?
      redirect_to login_path, alert: "Dev login is only available in development environment."
      return
    end
    
    email = params[:email] || 'caregiver@example.com'
    user = User.find_or_create_by!(email: email)
    
    # Authenticate user with Ahoy
    ahoy.authenticate(user)
    
    # Track dev login
    ahoy.track "Login Success", {
      method: "dev_login",
      client_type: "web_dashboard",
      ip: request.remote_ip,
      user_agent: request.user_agent
    }
    
    # Generate JWT
    payload = { uid: user.id, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, hmac_secret, "HS256")
    
    # Store in session
    session[:jwt_token] = token
    
    # Redirect to profile if name is not set
    if user.name.blank?
      redirect_to profile_path, notice: "Welcome! Please complete your profile to continue."
    else
      redirect_to dashboard_path, notice: "Logged in as #{user.display_name}"
    end
  end
  
  def destroy
    # Track logout event before clearing session
    if current_user
      ahoy.track "Logout", {
        client_type: "web_dashboard",
        ip: request.remote_ip,
        user_agent: request.user_agent
      }
    end
    
    session.delete(:jwt_token)
    cookies.delete(:jwt_token)
    redirect_to login_path, notice: "Logged out successfully"
  end
  
  private
  
  def current_user
    @current_user ||= begin
      token = session[:jwt_token] || cookies.encrypted[:jwt_token]
      payload = token && JWT.decode(token, hmac_secret, true, { algorithm: "HS256" }).first
      User.find_by(id: payload&.fetch("uid", nil))
    rescue JWT::DecodeError
      nil
    end
  end
  
  def hmac_secret
    ENV.fetch("JWT_SECRET", "dev_secret_change_me")
  end
end
