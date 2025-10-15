class SessionsController < ActionController::Base
  layout false
  
  def new
    # Show login page
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
