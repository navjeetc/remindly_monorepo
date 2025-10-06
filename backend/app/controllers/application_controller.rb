class ApplicationController < ActionController::API
  private

  def current_user
    @current_user ||= begin
      token = request.authorization&.split(" ")&.last
      payload = token && JWT.decode(token, hmac_secret, true, { algorithm: "HS256" }).first
      User.find_by(id: payload&.fetch("uid", nil))
    rescue JWT::DecodeError
      nil
    end
  end

  def authenticate!
    head :unauthorized unless current_user
  end

  def hmac_secret = ENV.fetch("JWT_SECRET", "dev_secret_change_me")
end
