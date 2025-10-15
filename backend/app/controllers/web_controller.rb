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
  
  helper_method :current_user
end
