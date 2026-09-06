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
  COOKIE_LIFETIME = 1.year

  private

  # The link is re-read from the database on every request rather than trusted
  # from the moment it was redeemed, so revoking one takes effect on the device's
  # next request — seconds — without anything having to chase cookies that were
  # already handed out.
  def link_mode_link
    return @link_mode_link if defined?(@link_mode_link)

    @link_mode_link = ReminderLink.live.find_by(id: cookies.signed[COOKIE])
  end

  def link_mode_user = link_mode_link&.user

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
