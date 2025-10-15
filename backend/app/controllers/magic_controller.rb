class MagicController < ApplicationController
  def request_link
    user  = User.find_or_create_by!(email: params.require(:email))
    token = user.signed_id(purpose: :magic_login, expires_in: 30.minutes)
    
    # Send magic link email
    MagicMailer.magic_link_email(user, token).deliver_later
    
    render json: { status: "sent" }
  end

  def verify
    token = params.require(:token)
    user  = User.find_signed(token, purpose: :magic_login)
    return head :unauthorized unless user
    render plain: issue_jwt(user:)
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
