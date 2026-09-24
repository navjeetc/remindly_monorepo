# frozen_string_literal: true

# Honouring a reminder link — the bookmarked address that lets one device act
# for one care receiver without signing in.
#
# This is a concern rather than a base class so that accepting the credential is
# something a controller has to *ask for*, by name, in one line somebody can
# grep. Two controllers include it today: the page the device leaves open, and
# the endpoint that marks a dose done. Every other controller in the application
# is unreachable with a link cookie because it never includes this, which is the
# property `docs/SENIOR_ACCESS_DESIGN.md` asks for — forgetting to opt in fails
# closed.
#
# The scoping that keeps one link to one person is not here: it is the
# `where(reminders: { user_id: current_user.id })` each action already does.
# This decides *who is acting*, never *what they may touch*.
module ReminderLinkMode
  extend ActiveSupport::Concern

  COOKIE = :reminder_link
  HEADER = "X-Reminder-Link"
  # The same thing for a plain form post, which cannot set a header. Named with
  # "token" so filter_parameters keeps it out of the logs.
  PARAM = :reminder_link_token
  COOKIE_LIFETIME = 1.year

  included do
    # The layout asks this to decide whether to offer a way back into the rest
    # of the app. Defined here so every controller that may honour a link can
    # answer it, rather than each one growing its own.
    helper_method :link_mode?, :reminder_link_form_params, :reminder_link_button_options if respond_to?(:helper_method)
  end

  private

  # The link is re-read from the database on every request rather than trusted
  # from the moment it was redeemed, so revoking one takes effect on the device's
  # next request — seconds — without anything having to chase cookies that were
  # already handed out.
  # The link a request carries, preferring the one it names explicitly.
  #
  # The device page sends its own link in X-Reminder-Link on every request, and
  # that wins over the cookie. The cookie is one per browser, shared by every
  # window -- incognito ones included -- and holds whichever link was opened
  # last, so reading it alone made two windows on two people's links show the
  # same person, each under its own address.
  #
  # A header that names a dead link does not fall back to the cookie. The page
  # asked for one person; answering with whoever the cookie happens to hold is
  # exactly the mix-up this exists to end, and a revoked link should land the
  # device on its unavailable screen like any other.
  def link_mode_link
    return @link_mode_link if defined?(@link_mode_link)

    presented = request.headers[HEADER].presence || params[PARAM].presence
    @link_presented_in_header = presented.present?
    return @link_mode_link = ReminderLink.live_by_token(presented) if presented

    @link_mode_link = ReminderLink.live.find_by(id: cookies.signed[COOKIE])
  end

  def link_presented_in_header? = @link_presented_in_header == true

  # For the device page's buttons: an empty field the page fills in from its
  # own address as it loads (see the script at the foot of the voice layout).
  #
  # Empty on purpose. The token is already in the address bar, where it has to
  # be for the bookmark to work, and it is deliberately never printed into the
  # page itself -- a screenshot or a saved page must not carry the credential.
  # Filling it from the address keeps both promises.
  def reminder_link_form_params
    { PARAM => "" }
  end

  def link_mode_user = link_mode_link&.user

  # Whom a request speaks for, when it may carry a session and a link at once.
  #
  # The link wins when the two name different people. It used to be the other
  # way round everywhere a link was honoured, and a browser signed in as one care
  # receiver that then opened another's link showed the *signed-in* person's
  # reminders and appointments under the other person's address -- the URL
  # naming one person and the screen belonging to somebody else. Found in
  # production, by opening a newly created care receiver's link in a window that
  # was signed in as a different one: the new account's consent question never
  # appeared, and the other person's day did.
  #
  # The link is the deliberate credential. It is minted for exactly one person,
  # opened on purpose, and says so in the address bar; a session is ambient, and
  # may be left over from anything. Honouring the link cannot grant more than
  # holding it already does, and costs the session nothing but the view on this
  # one page.
  #
  # When they agree, or only one is present, nothing changes.
  def resolve_person(session_user)
    link_user = link_mode_user

    # A page that named its link and was refused is answered by nobody. Without
    # this a revoked link in a signed-in browser fell through to the session,
    # and the page showed -- and Done acted for -- the signed-in person under an
    # address that names somebody else.
    return nil if link_presented_in_header? && link_user.nil?

    return session_user || link_user if link_user.nil? || session_user.nil?
    return session_user if link_user.id == session_user.id

    # Only a link this request names outranks a session: the header, the form
    # field, or /r/<token> in the address. A cookie left over from opening
    # somebody's link earlier does not. Letting it would make plain
    # /voice_reminders, visited by a signed-in person, show whichever link this
    # browser last opened -- the same mix-up, from the other side.
    return session_user unless explicit_link?

    @link_overrides_session = true
    link_user
  end

  # Whether the link in play was named by this request rather than remembered by
  # the browser. The page opened at /r/<token> sets @link_from_address.
  def explicit_link? = link_presented_in_header? || @link_from_address == true

  # For the device page's buttons on a page opened from a link: disabled until
  # the page has filled in its own link.
  #
  # Without JavaScript the field would stay empty and the post would answer with
  # the browser-wide cookie -- whichever link was opened last, in any window --
  # and "No thank you" deletes an account. Disabled is the safe failure: the
  # buttons do nothing rather than act for somebody else. The consent question
  # can still be answered by telephone. A page reached without a link has no
  # link to fill in, and its buttons are left alone.
  def reminder_link_button_options
    return {} if params[:token].blank?

    { disabled: true, data: { needs_reminder_link: true } }
  end

  def link_overrides_session? = @link_overrides_session == true

  # Whether the person looking got here on a reminder link rather than a
  # session. Overridden in VoiceRemindersController, which knows which
  # credential actually answered; everywhere else a link cookie being present is
  # the whole story.
  def link_mode? = link_mode_link.present?

  def remember_reminder_link(link)
    cookies.signed[COOKIE] = {
      value: link.id,
      expires: COOKIE_LIFETIME.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    @link_mode_link = link
  end
end
