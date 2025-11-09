class DevController < WebController
  # DEV ONLY: Quick user switching for testing
  before_action :check_development_environment!
  
  def switch_user
    user = User.find(params[:user_id])
    
    # Generate new JWT token for the user
    payload = { uid: user.id }
    token = JWT.encode(payload, hmac_secret, "HS256")
    
    # Store in session
    session[:jwt_token] = token
    
    redirect_to dashboard_path, notice: "Switched to #{user.display_name}"
  end
  
  private
  
  def check_development_environment!
    unless Rails.env.development?
      redirect_to root_path, alert: "This feature is only available in development"
    end
  end
  
  def hmac_secret = ENV.fetch("JWT_SECRET", "dev_secret_change_me")
end
