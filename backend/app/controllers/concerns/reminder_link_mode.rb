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
  COOKIE_LIFETIME = 1.year

  included do
    # The layout asks this to decide whether to offer a way back into the rest
    # of the app. Defined here so every controller that may honour a link can
    # answer it, rather than each one growing its own.
    helper_method :link_mode? if respond_to?(:helper_method)
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

    presented = request.headers[HEADER].presence
    @link_presented_in_header = presented.present?
    return @link_mode_link = ReminderLink.live_by_token(presented) if presented

    @link_mode_link = ReminderLink.live.find_by(id: cookies.signed[COOKIE])
  end

  def link_presented_in_header? = @link_presented_in_header == true

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
    return session_user || link_user if link_user.nil? || session_user.nil?
    return session_user if link_user.id == session_user.id

    @link_overrides_session = true
    link_user
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
