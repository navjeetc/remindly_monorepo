# Two different clients acknowledge reminders, and they authenticate differently:
#
#   /voice_reminders   Rails page, session cookie + CSRF token (what seniors use)
#   /client/           static JS app, Authorization: Bearer <jwt>, no CSRF token
#
# Inheriting from WebController alone rejected the Bearer client at the forgery
# check (422); inheriting from ApplicationController alone rejected the session
# client, because its current_user only reads the Authorization header (401).
# Either choice breaks one of them, so this accepts both.
class AcknowledgementsController < WebController
  # Only skip forgery protection for requests that carry a Bearer token, which a
  # browser will not send cross-site. Session requests keep CSRF protection.
  skip_forgery_protection if: -> { bearer_user.present? }

  before_action :authenticate!

  def create
    occ  = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    kind = params.require(:kind)
    Acknowledgement.create!(occurrence: occ, kind:, at: Time.current)
    occ.update!(status: :acknowledged)
    head :created
  end

  def snooze
    occ = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    minutes = params.fetch(:minutes, 10).to_i # Default 10 minutes
    
    # Create acknowledgement for snooze tracking
    Acknowledgement.create!(occurrence: occ, kind: 'snooze', at: Time.current)
    
    # Create new occurrence for snoozed time
    new_occ = Occurrence.create!(
      reminder: occ.reminder,
      scheduled_at: minutes.minutes.from_now,
      status: :pending
    )
    
    # Mark original as acknowledged
    occ.update!(status: :acknowledged)
    
    render json: {
      snoozed_occurrence_id: new_occ.id,
      scheduled_at: new_occ.scheduled_at,
      minutes: minutes
    }, status: :created
  end

  private

  # Bearer first (the JS client), falling back to WebController's session lookup
  # (the /voice_reminders page).
  def current_user
    @current_user ||= bearer_user || super
  end

  def bearer_user
    return @bearer_user if defined?(@bearer_user)

    @bearer_user = begin
      token = request.authorization&.split(" ")&.last
      payload = token && JWT.decode(token, hmac_secret, true, { algorithm: "HS256" }).first
      User.find_by(id: payload&.fetch("uid", nil))
    rescue JWT::DecodeError
      nil
    end
  end

  # WebController redirects to the login page when unauthenticated, which is
  # meaningless to both of these clients — they want a status code.
  def authenticate!
    head :unauthorized unless current_user
  end
end
