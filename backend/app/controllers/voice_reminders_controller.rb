# frozen_string_literal: true

# The page a care receiver's device leaves open all day, and the JSON it polls.
#
# Extracted from DashboardController, which authenticates every action through
# `current_user` and a caregiver-shaped session. This page is the one place a
# second kind of credential is going to be honoured — a reminder link, where the
# secret in a bookmarked URL is the whole credential — and that must not become
# a flag inside a controller whose other twenty actions manage caregivers,
# permissions and telephone numbers.
#
# Its own controller makes the boundary structural: a link-mode cookie is read
# here and nowhere else, so a route added to the dashboard tomorrow cannot
# accidentally accept one. Forgetting to opt a controller in fails closed,
# which is the property `docs/SENIOR_ACCESS_DESIGN.md` asks for and the reason
# this is a separate file rather than two more `before_action` exceptions.
class VoiceRemindersController < WebController
  include ReminderLinkMode
  # Redeeming happens here rather than in a controller of its own, so that the
  # bookmarkable address and the page it shows are the same address. See
  # #redeem_token.
  #
  # Guessing 32 bytes is not a real threat; the limit is here so enumeration
  # attempts cost something and do not quietly fill the logs.
  rate_limit to: 20, within: 1.minute, only: :show, if: -> { params[:token].present? }

  before_action :redeem_token, only: :show
  before_action :authenticate!, only: :show
  before_action :authenticate_poll!, only: :today
  before_action :care_receivers_only!, only: :show

  layout "voice"

  helper_method :voice_script_version

  def show; end

  # The script's own modification time, so the cache busts when the file
  # changes rather than every second. Memoised per process: this is a stat call
  # on a page a device reloads all day, and the file cannot change without a
  # deploy, which restarts the process.
  def voice_script_version = self.class.script_version

  def self.script_version
    @script_version ||= File.mtime(Rails.public_path.join("voice_reminders.js")).to_i
  rescue Errno::ENOENT
    # Missing in a way that would only happen mid-deploy or in a broken image.
    # A page that renders without a cache-buster beats a page that 500s.
    0
  end

  # Polled by public/voice_reminders.js. Everything due today and still pending,
  # in the care receiver's own timezone — the announcement decides what to say
  # from this, so it deliberately does not filter on how the row was created.
  def today
    # Answered as JSON whatever the request's format, which is how this endpoint
    # behaved before it moved. Deciding by format instead would make the refusal
    # depend on whether the caller sent an Accept header — so a hand-made
    # request would get a redirect where fetch() gets a 401, and the boundary
    # would read differently depending on who was knocking.
    return render json: { error: "Unauthorized" }, status: :unauthorized unless current_user.role_senior?

    # One clock reading, not two. Asking tz.now twice means a request that
    # straddles midnight can take its start from one day and its end from the
    # next — a forty-eight hour window, on the endpoint that decides what a care
    # receiver is told to do today. The version this was extracted from read the
    # clock once; the extraction is what introduced the second call.
    now = ActiveSupport::TimeZone[current_user.tz].now
    day = now.beginning_of_day..now.end_of_day

    # includes as well as joins: the join scopes the query, and without the
    # include every occurrence costs another query to read its title — on the
    # endpoint a tablet polls every few seconds, all day. Two queries instead of
    # one per reminder, on the device this page is deliberately light for.
    occurrences = Occurrence
      .joins(:reminder)
      .includes(:reminder)
      .where(reminders: { user_id: current_user.id })
      .where(scheduled_at: day)
      .where(status: :pending)
      .order(:scheduled_at)

    render json: occurrences.map { |occ|
      {
        id: occ.id,
        title: occ.reminder.title,
        description: occ.reminder.notes || "",
        scheduled_at: occ.scheduled_at,
        acknowledged_at: (occ.status == "acknowledged" ? occ.updated_at : nil),
        snoozed_until: nil
      }
    }
  end

  private

  # The poll answers with a status rather than a redirect.
  #
  # WebController's authenticate! redirects to the login page, which is the
  # right answer for somebody typing a URL and the wrong one for fetch(): the
  # browser follows the redirect, hands back a 200 full of HTML, the JSON parse
  # throws, and the page goes on showing the reminders it already had. A device
  # whose link was revoked an hour ago would keep announcing them, and the
  # screen would look exactly as it does when everything is fine.
  #
  # A 401 is something the client can act on, and it does — see the reload in
  # public/voice_reminders.js.
  def authenticate_poll!
    return if current_user

    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  # `GET /r/<token>` renders this page directly. It used to set the cookie and
  # redirect here, which put the token out of the address bar — and quietly
  # broke the promise the whole feature exists to keep.
  #
  # The bookmark is the credential. A caregiver follows the instruction on the
  # panel — open it on the tablet, then bookmark it — and after a redirect the
  # address bar says `/voice_reminders`, so what gets saved, or added to the
  # home screen, is a tokenless address that works only while the cookie lives.
  # Clear the cookies six months later and that bookmark lands on a login page:
  # exactly the failure this was built to end, reintroduced by the redirect that
  # was tidying the URL.
  #
  # So the token stays in the address bar. What that costs is history and
  # shoulder-surfing on the care receiver's own device; what it buys is a
  # bookmark that still works after a device reset. The referrer leak the
  # redirect was also guarding against is closed a different way — this page
  # loads no third-party assets at all, which a spec asserts.
  #
  # The cookie is still set, because the JSON the page polls lives at another
  # path and needs a credential of its own.
  def redeem_token
    return if params[:token].blank?

    link = ReminderLink.live_by_token(params[:token])

    # A revoked token and a made-up one are answered identically. Distinguishing
    # them would tell whoever holds a dead link that it was once real, and tell
    # an enumerator which guesses were close.
    #
    # A page rather than an empty 404. The device reloads its own bookmark when
    # its credential stops working, so this is what a care receiver is left
    # looking at — and `head :not_found` left them looking at nothing at all,
    # with no way to tell a revoked link from a broken tablet.
    return render :unavailable, status: :not_found unless link

    remember_reminder_link(link)
    link.record_use_if_stale!
  end

  # Session first, then link mode.
  #
  # This override is the entire opt-in, and it lives in one controller on
  # purpose. Nothing else in the application reads the reminder-link cookie, so
  # a route added to the dashboard next year cannot accept one by forgetting
  # something — it would have to ask for it. That is what makes the boundary a
  # wall rather than a flag.
  # @session_user is assigned on the same expression that resolves it, so it is
  # nil exactly when the session credential did not authenticate — including
  # when a JWT is present but expired, which is the case this page exists for.
  # Asking whether a token is merely *present* got that backwards: a tablet
  # carrying a stale JWT would have been treated as signed in, and shown Done
  # and Snooze buttons that its credential can no longer honour.
  def current_user
    @current_user ||= (@session_user = super) || link_mode_user
  end

  # The link is re-read from the database on every request rather than trusted
  # from the moment it was redeemed, so revoking one takes effect on the care
  # receiver's next poll — seconds — without anything having to chase cookies
  # that were already handed out.
  # Wrapped so that a device polling this page keeps its "last heard from"
  # fresh, and keeps its cookie. The concern's own lookup stays side-effect
  # free, because the acknowledgement endpoint includes it too and a write per
  # keypress there would be recording the same fact twice.
  #
  # Sliding the expiry matters more than it looks. The cookie was set once, for
  # a year, and never renewed — so a tablet in continuous daily use would have
  # silently lost its authorisation on the anniversary of the day it was set up,
  # landing on a login page nobody reads. That is precisely the failure this
  # whole feature exists to end, arriving twelve months later instead of one.
  #
  # Renewed on the same throttle as the timestamp, so a device polling every few
  # seconds writes one cookie every ten minutes rather than one per request.
  def link_mode_link
    link = super
    remember_reminder_link(link) if link&.record_use_if_stale!
    link
  end

  # Asked directly rather than inferred from which branch of `current_user`
  # happened to fire.
  #
  # This used to read a flag that `link_mode_user` set as a side effect, which
  # was correct only for as long as nobody reordered `current_user` — and what
  # depends on the answer is whether the layout shows Sign Out and Profile to
  # somebody with no account. A guarantee that survives a refactor is worth more
  # than one that happens to hold today.
  def link_mode?
    current_user

    @session_user.nil? && current_user.present? && link_mode_link.present?
  end
  helper_method :link_mode?

  # A caregiver reaching this page has nothing to hear: the reminders belong to
  # the person being cared for. The redirect is kept from the original rather
  # than a 403, because a caregiver arriving here has made a navigation mistake,
  # not an authorisation attempt.
  def care_receivers_only!
    return if current_user.role_senior?

    redirect_to dashboard_path, alert: "Voice reminders are only available for care receivers"
  end
end
