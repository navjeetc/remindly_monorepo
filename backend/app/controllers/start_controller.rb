# frozen_string_literal: true

# `remindly.care/start` — six digits, typed on the care receiver's own device.
#
# Short enough to say down a telephone and short enough to type on a tablet,
# which is the whole reason it exists: it is how a caregiver in another city
# gets a reminder link onto their mother's screen without asking her to find an
# email and trust a link inside it.
#
# This is the second controller allowed to hand out a link-mode cookie, and it
# says so by including the concern. Everything else in the application is
# unreachable with one because it never mentions it.
class StartController < WebController
  include ReminderLinkMode

  layout "voice"

  # Six digits is a million possibilities, which is worth guessing at without a
  # limit and not worth it with one. Per IP, because the code is the secret and
  # the attacker chooses the code, not the account.
  rate_limit to: 10, within: 5.minutes, only: :create

  def show; end

  def create
    link = ReminderLink.claim_start_code(params[:code])

    # A wrong code, an expired one and a spent one are answered identically. Any
    # difference between them tells somebody guessing which guesses were close,
    # and tells whoever holds a stale code that it was once real.
    unless link
      flash.now[:alert] = "That code did not work. Ask them to read you a new one."
      return render :show, status: :unprocessable_entity
    end

    remember_reminder_link(link)
    link.record_use_if_stale!

    # To the link's own address rather than straight to the reminders, so the
    # device lands on the address it should bookmark — the same reason /r/:token
    # renders instead of redirecting.
    redirect_to reminder_link_path(token: link.token)
  end
end
