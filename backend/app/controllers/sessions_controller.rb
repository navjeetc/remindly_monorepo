class SessionsController < ActionController::Base
  layout false
  
  def new
    # Show login page
  end
  
  # Request magic link via email
  def request_magic_link
    email = params[:email]
    user = User.find_or_create_by!(email: email)
    token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
    
    # Send magic link email
    MagicMailer.magic_link_email(user, token, web: true).deliver_later
    
    redirect_to login_path, notice: "Magic link sent! Check your email to sign in."
  end
  
  # Verify magic link and log in
  def verify_magic_link
    token = params[:token]
    user = User.find_signed(token, purpose: :magic_login)
    
    if user
      # Generate JWT and store in session
      payload = { uid: user.id, exp: 30.days.from_now.to_i }
      jwt_token = JWT.encode(payload, hmac_secret, "HS256")
      session[:jwt_token] = jwt_token
      
      redirect_to dashboard_path, notice: "Successfully signed in as #{user.email}"
    else
      redirect_to login_path, alert: "Invalid or expired magic link. Please try again."
    end
  end
  
  # Dev mode quick login
  def dev_login
    email = params[:email] || 'caregiver@example.com'
    user = User.find_or_create_by!(email: email)
    
    # Generate JWT
    payload = { uid: user.id, exp: 30.days.from_now.to_i }
    token = JWT.encode(payload, hmac_secret, "HS256")
    
    # Store in session
    session[:jwt_token] = token
    
    redirect_to dashboard_path, notice: "Logged in as #{user.email}"
  end
  
  def destroy
    session.delete(:jwt_token)
    cookies.delete(:jwt_token)
    redirect_to login_path, notice: "Logged out successfully"
  end
  
  private
  
  def hmac_secret
    ENV.fetch("JWT_SECRET", "dev_secret_change_me")
  end
end
