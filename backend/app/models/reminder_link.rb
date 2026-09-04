# frozen_string_literal: true

# A bookmarkable URL that lets one device hear one care receiver's reminders
# without signing in — a capability URL, where the secret in the address *is*
# the credential, like a calendar feed.
#
# It exists because the alternative fails every month: a care receiver's session
# expires, the tablet shows a login page nobody reads, and the first anyone
# knows is a caregiver noticing the acknowledgements stopped, or not noticing.
# A bookmark survives what a session does not — cookie loss, a cleared browser,
# a restarted device — because the credential is in the bookmark rather than in
# the cookie jar.
#
# What it grants is deliberately small, and enforced by VoiceRemindersController
# being the only place the cookie is read. See docs/SENIOR_ACCESS_DESIGN.md.
class ReminderLink < ApplicationRecord
  belongs_to :user

  TOKEN_BYTES = 32

  # Revoked links are kept rather than deleted. A caregiver asking "did we ever
  # set up the old tablet, and when did it last work" is asking about a row that
  # deleting would have thrown away — and `last_used_at` on a revoked row is the
  # only record that a device was ever really used.
  scope :live, -> { where(revoked_at: nil) }

  # Looked up by token alone, so this is the whole authorisation decision. A
  # revoked link and an unknown one both return nil, which is what lets the
  # controller answer them identically: a revoked token must 404 like any string
  # somebody made up, or the 404 itself tells an attacker which tokens were real.
  def self.live_by_token(token)
    return nil if token.blank?

    live.find_by(token: token)
  end

  # Minted for a care receiver, letting the database settle a token collision
  # rather than checking for one first.
  #
  # Two unique indexes can refuse this insert and they mean opposite things. A
  # duplicate token is astronomically unlikely, means nothing, and should simply
  # be tried again. A second *live* link for the same person is a real refusal —
  # the caller is trying to leave two credentials outstanding — and retrying it
  # would burn three attempts to arrive at the same answer. So they are told
  # apart rather than swallowed together.
  def self.mint(user:)
    attempts = 0

    begin
      create!(user: user, token: SecureRandom.urlsafe_base64(TOKEN_BYTES))
    rescue ActiveRecord::RecordNotUnique => e
      raise if live.exists?(user_id: user.id)

      attempts += 1
      raise e if attempts > 3

      retry
    end
  end

  def revoked? = revoked_at.present?

  # Revoking is the care receiver's ending as much as the caregiver's: the
  # design requires somebody who never signs in to be able to refuse, and this
  # is what "stop this" writes. It ends the link and nothing else — it cannot
  # remove a caregiver's access, because a leaked URL that could cut a family
  # off from a vulnerable person is a worse outcome than the one it prevents.
  def revoke!
    update!(revoked_at: Time.current) unless revoked?
    self
  end

  # How often a live device is allowed to write down that it is alive.
  #
  # The page polls every few seconds. Recording each one would be a write per
  # poll per device, all day, to say something that only changes meaning over
  # hours — and "last heard from" is read in hours.
  USE_RECORDED_EVERY = 10.minutes

  # Written on every use so a caregiver can tell a live device from one that
  # silently stopped. update_column rather than touch: this runs on a page load
  # the care receiver is waiting for, it must not fire callbacks or bump
  # updated_at, and nothing about it is worth a validation pass.
  def record_use!(at: Time.current)
    update_column(:last_used_at, at)
  end

  # Called on every request the link authorises, not only when it is redeemed.
  #
  # Redemption happens once — the device visits /r/<token>, gets a cookie, and
  # then polls for months without touching that route again. Recording only
  # there would have left the panel saying "last heard from 3 months ago" about
  # a tablet that had been working perfectly all along, which is worse than
  # saying nothing: the one number a caregiver would use to spot a dead device
  # would be wrong in exactly the direction that causes a false alarm.
  def record_use_if_stale!(at: Time.current)
    return if last_used_at.present? && last_used_at > at - USE_RECORDED_EVERY

    record_use!(at: at)
  end
end
