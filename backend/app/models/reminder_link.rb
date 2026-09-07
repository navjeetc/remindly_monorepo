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

  # How long six digits are worth anything. Long enough to read them down a
  # telephone and have somebody type them; short enough that a guessed code is
  # not worth attempting, alongside the rate limit at the endpoint.
  START_CODE_TTL = 10.minutes

  # Digits, so they can be said aloud without spelling anything, and generated
  # with SecureRandom rather than rand — a predictable setup code would be a
  # predictable way into somebody's reminders.
  def issue_start_code!(at: Time.current)
    # Give back the digits nobody is going to type.
    #
    # The unique index is global and covers every non-null code, so a code that
    # expired unspent keeps its six digits reserved forever. Nothing ever
    # released them: only *spending* a code cleared it. The namespace is a
    # million values and it only ever shrank, so collisions in the loop below
    # would climb until issuing a code raised after five attempts — years away
    # and monotonic, which is the kind of failure that arrives with no warning
    # and no obvious cause.
    #
    # Swept on issue rather than by a job: this is the only moment the shortage
    # would ever matter, and a table that repairs itself needs no schedule.
    self.class.where.not(start_code: nil)
        .where(start_code_expires_at: ...at)
        .update_all(start_code: nil, start_code_expires_at: nil, updated_at: at)

    attempts = 0

    begin
      update!(start_code: format("%06d", SecureRandom.random_number(1_000_000)),
              start_code_expires_at: at + START_CODE_TTL)
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts > 5

      retry
    end

    self
  end

  # Claims a code and spends it, atomically, returning the link or nil.
  #
  # Single use is the point: the WHERE clause carries every condition — the
  # digits, an unexpired deadline, an unrevoked link — so two people racing the
  # same code cannot both be let in, and a code cannot be replayed the moment
  # after it works. Whoever loses sees zero rows and is answered exactly as a
  # wrong code is.
  def self.claim_start_code(code, at: Time.current)
    return nil if code.blank?

    link = live.find_by(start_code: code.to_s.strip)
    return nil unless link
    return nil if link.start_code_expires_at.nil? || link.start_code_expires_at < at

    # Every condition the check made, carried into the write. Without the
    # expiry and the revocation here, a code that lapsed — or a link revoked —
    # between reading the row and spending it would still be accepted, which is
    # exactly the gap the compare-and-swap was meant to close.
    spent = live
              .where(id: link.id, start_code: link.start_code)
              .where(start_code_expires_at: at..)
              .update_all(start_code: nil, start_code_expires_at: nil, updated_at: at)

    spent.zero? ? nil : link.reload
  end

  def start_code_live?(at: Time.current)
    start_code.present? && start_code_expires_at.present? && start_code_expires_at > at
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
  # Returns whether it actually wrote, which the caller uses to decide whether
  # to slide the cookie's expiry forward at the same time — the two are the same
  # question ("has this device been heard from lately") answered in two places,
  # and doing them together keeps them from disagreeing.
  def record_use_if_stale!(at: Time.current)
    return false if last_used_at.present? && last_used_at > at - USE_RECORDED_EVERY

    record_use!(at: at)
    true
  end
end
