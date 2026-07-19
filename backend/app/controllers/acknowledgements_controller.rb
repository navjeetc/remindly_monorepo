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
  # Skip forgery protection only for the Bearer scheme this API uses. Matching any
  # Authorization header would also disable CSRF for Basic auth injected by a
  # reverse proxy, which has nothing to do with this client.
  #
  # Keying this on bearer_user.present? instead would mean an expired or invalid
  # JWT falls through to the CSRF check and returns 422, when the honest answer is
  # 401. The scheme decides whether CSRF applies; the token's validity decides
  # whether the request is authenticated.
  skip_forgery_protection if: -> { bearer_scheme? }

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

  # A Bearer header is a claim about who is acting, so it decides the outcome on
  # its own: if it is present but invalid, the request is unauthenticated, not
  # session-authenticated.
  #
  # Falling back to the session here would be wrong in a way that is easy to miss.
  # A same-origin fetch from /client sends the session cookie alongside its Bearer
  # header, so an expired token would quietly succeed as whoever owns the browser
  # session instead of returning 401 — no stale-token logout, and one user's
  # stale action applied to another's account.
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = bearer_scheme? ? bearer_user : super
  end

  # RFC 7235 makes auth scheme names case-insensitive, so "bearer <token>" is as
  # valid as "Bearer <token>". A case-sensitive check would treat the lowercase
  # form as a session request: CSRF would apply and it would fail with 422
  # instead of the intended 401.
  def bearer_scheme?
    bearer_parts.first&.casecmp?("Bearer") || false
  end

  def bearer_parts
    @bearer_parts ||= request.authorization.to_s.split(/\s+/, 2)
  end

  def bearer_user
    return @bearer_user if defined?(@bearer_user)
    return @bearer_user = nil unless bearer_scheme?

    @bearer_user = begin
      token = bearer_parts.last
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
