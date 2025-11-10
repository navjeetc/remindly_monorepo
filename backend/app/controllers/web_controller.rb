class WebController < ActionController::Base
  protect_from_forgery with: :exception
  
  private

  def current_user
    @current_user ||= begin
      # Try to get JWT from session or cookie
      token = session[:jwt_token] || cookies.encrypted[:jwt_token]
      payload = token && JWT.decode(token, hmac_secret, true, { algorithm: "HS256" }).first
      User.find_by(id: payload&.fetch("uid", nil))
    rescue JWT::DecodeError
      nil
    end
  end

  def authenticate!
    unless current_user
      redirect_to login_path
      return
    end
  end

  def hmac_secret = ENV.fetch("JWT_SECRET", "dev_secret_change_me")
  
  # DEV ONLY: Get users grouped by role for dev switcher
  def dev_users_by_role
    return {} unless Rails.env.development?
    
    @dev_users_by_role ||= {
      caregivers: User.where(role: :caregiver).order(:name),
      seniors: User.where(role: :senior).order(:name)
    }
  end
  
  helper_method :current_user, :dev_users_by_role
end
