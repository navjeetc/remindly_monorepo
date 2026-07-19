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

  # Snoozing must never move a reminder earlier. The senior UI shows Snooze before
  # the scheduled time, so "10 minutes from now" would reschedule a 10:25 reminder
  # tapped at 10:00 to 10:10 — 15 minutes *earlier* than it was already going to
  # arrive, which is the opposite of what the word means.
  SNOOZE_DEFAULT_MINUTES = 10
  SNOOZE_MIN_MINUTES = 1

  def snooze
    occ = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    minutes = snooze_minutes

    # Measure from whichever is later: the time it was due, or now. Before the due
    # time that delays the original; after it, it delays from the moment the
    # senior asked.
    base = [ occ.scheduled_at, Time.current ].max
    target = base + minutes.minutes

    # Making the target deterministic also makes a retry collide: occurrences are
    # unique on (reminder_id, scheduled_at), so a second request for the same
    # snooze — a lost response, a double tap — would raise RecordNotUnique and
    # return 500 for a snooze that had already succeeded. The same collision
    # occurs when the target lands on an already-materialised recurrence.
    #
    # find_or_create_by makes the retry idempotent, and the transaction keeps a
    # failure from leaving the acknowledgement behind without its occurrence.
    new_occ = nil
    ActiveRecord::Base.transaction do
      Acknowledgement.create!(occurrence: occ, kind: 'snooze', at: Time.current)

      new_occ = Occurrence.find_or_create_by!(reminder: occ.reminder, scheduled_at: target) do |o|
        o.status = :pending
      end

      occ.update!(status: :acknowledged)
    end
    
    render json: {
      snoozed_occurrence_id: new_occ.id,
      scheduled_at: new_occ.scheduled_at,
      minutes: minutes
    }, status: :created
  end

  private

  # Strict parsing, because to_i turns "not-a-number" into 0 — which then clamps to
  # one minute rather than falling back to the default, quietly making the snooze
  # far shorter than the senior expected. Anything unparseable or missing means we
  # do not know what was asked for, so use the default; a value we can read but
  # that is too small is a different case and gets clamped.
  def snooze_minutes
    parsed = Integer(params[:minutes].to_s, exception: false)
    return SNOOZE_DEFAULT_MINUTES if parsed.nil?

    [ parsed, SNOOZE_MIN_MINUTES ].max
  end

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
