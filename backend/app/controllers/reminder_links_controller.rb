# frozen_string_literal: true

# Redeems a reminder link: `GET /r/<token>`.
#
# The token is exchanged for a signed cookie and dropped from the address bar,
# so it stops appearing in browser history, in referrer headers and over the
# shoulder of anyone reading the screen. The bookmark still holds the token,
# which is the point — clearing cookies or resetting the tablet recovers by
# itself, where a long-lived session would simply be gone.
class ReminderLinksController < WebController
  # No authenticate!. This is the one route whose whole purpose is to be reached
  # by somebody who cannot sign in.
  #
  # Guessing 32 bytes is not a real threat; the limit is here so enumeration
  # attempts cost something and do not quietly fill the logs.
  rate_limit to: 20, within: 1.minute, only: :show

  # The cookie identifies the link, not the user. A revoked link therefore stops
  # working on the next request without anything having to hunt down cookies
  # that were already handed out — revocation is a property of the row, checked
  # every time, rather than a promise made once at redemption.
  COOKIE = :reminder_link
  COOKIE_LIFETIME = 1.year

  def show
    link = ReminderLink.live_by_token(params[:token])

    # A revoked token and a made-up one are answered identically. Distinguishing
    # them would tell whoever is holding a dead link that it was once real, and
    # tell an enumerator which guesses were close.
    return head :not_found unless link

    link.record_use!

    cookies.signed[COOKIE] = {
      value: link.id,
      expires: COOKIE_LIFETIME.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    redirect_to voice_reminders_path
  end
end
