class TelnyxCall < ApplicationRecord
  belongs_to :occurrence
  belongs_to :user

  # Nullable: an attempt is claimed before the provider is called, so the id
  # only arrives afterwards.
  validates :call_control_id, uniqueness: true, allow_nil: true
  validates :status, presence: true
  validates :outcome, presence: true

  STATUSES = %w[
    pending
    reserved
    initiated
    ringing
    answered
    speaking
    gathering
    completed
    failed
    cancelled
    hangup
  ].freeze

  # taken and snooze mirror the two buttons the senior UI offers. no_response is
  # what an unanswered or silent call leaves behind -- deliberately not "skip",
  # because nobody chose anything, and the occurrence stays pending so the missed
  # sweep can still claim it.
  OUTCOMES = %w[
    pending
    taken
    snooze
    skip
    no_response
    error
  ].freeze

  # The design document allows "no answer or busy retries after a few minutes,
  # twice at most, then stops" -- three attempts in all. How many, and how far
  # apart, is still an open question there; both are named so changing the
  # policy is one edit and the specs assert against these rather than literals.
  MAX_ATTEMPTS = 3
  RETRY_AFTER = 5.minutes

  # A ceiling on calls to one person in one day, which MAX_ATTEMPTS cannot give:
  # that is per occurrence, so a senior with six reminders due could take
  # eighteen calls and never exceed it. Invariant 7 of the design document
  # requires this and requires that a caregiver cannot configure it away, which
  # is why it is a constant here rather than a column on anything they can edit.
  #
  # Ten allows roughly three reminders a day to exhaust their retries. The right
  # number is an open question in the document, alongside how many retries and
  # how far apart; it is named so changing it is one edit.
  MAX_CALLS_PER_DAY = 10

  # Claims the next attempt for an occurrence BEFORE anything is dialled.
  #
  # The order matters. Reserving after the provider call, or not at all, means
  # two scheduler runs (or a redelivered job) can both POST and the senior's
  # phone rings twice for one dose -- neither run can see the other, because
  # nothing has been written yet. Reserving first makes the unique index on
  # (occurrence_id, attempt_number) the thing that decides the race: both
  # compute the same next number, the database accepts one, and the loser is
  # told before it dials rather than after.
  #
  # Returns nil when this attempt is not ours to make -- another run won it, the
  # cap is reached, or the last attempt is too recent to follow up yet.
  def self.reserve(occurrence, user, now: Time.current)
    previous = where(occurrence_id: occurrence.id).order(:attempt_number).last

    return nil if previous && previous.attempt_number >= MAX_ATTEMPTS
    return nil if previous && previous.created_at > now - RETRY_AFTER
    day = local_day(user, now)

    # A fixed set of slots, not a moving counter. The previous shape read a count
    # and then a separate maximum, which two workers defeat trivially: both pass
    # the count at nine, the first takes slot ten, the second then reads a
    # maximum of ten and takes eleven. Nothing collides and eleven calls go out.
    #
    # There are exactly MAX_CALLS_PER_DAY slots in a day. Two reserves racing
    # both compute the same lowest free one, the unique index accepts one, and
    # the loser is told before it dials. A released slot is reusable, so an
    # attempt that never rang gives its allowance back without leaving a hole
    # that a dense counter could not fill.
    # One call at a time, per person. Nothing else enforces this: the daily cap
    # bounds the day and MAX_ATTEMPTS bounds the occurrence, but neither bounds
    # concurrency — so a dose falling due at the same moment as another
    # occurrence's retry dials the same phone twice at once. A live test did
    # exactly that: two calls in the same second, one answered and one left
    # talking to voicemail, having burned a slot on a call that could not
    # possibly be picked up. To the person holding the phone that is
    # indistinguishable from being robocalled.
    #
    # The skipped occurrence is not lost. It stays pending and the scheduler,
    # which runs every minute, offers it again once the line is free.
    return nil if call_in_flight?(user, now)

    slot = free_slot(user, day)
    return nil if slot.nil?

    # A zone change must not hand back a fresh day. call_day comes from users.tz,
    # which a caregiver can edit, and at 00:30 UTC Tokyo and Los Angeles are on
    # different dates — so without this the cap is configurable away, the one
    # thing invariant 7 says it must not be.
    #
    # Counted by comparing the zone each attempt was filed under, not by a
    # rolling window: a window wide enough to catch this also refuses a
    # legitimate morning call after a full evening, which is normal operation
    # rather than an anomaly. When the zone has not changed, nothing here counts.
    return nil if (slots_used(user, day) + slots_under_other_zones(user, zone_name(user), now)) >= MAX_CALLS_PER_DAY

    create!(
      occurrence: occurrence,
      user: user,
      attempt_number: (previous&.attempt_number || 0) + 1,
      call_day: day,
      call_tz: zone_name(user),
      daily_sequence: slot,
      status: "reserved",
      outcome: "pending"
    )
  rescue ActiveRecord::RecordNotUnique
    # Must not be called inside an outer transaction. Swallowing a constraint
    # violation leaves the enclosing transaction unusable on PostgreSQL, and
    # every later statement in it fails -- so the loser of the race would take
    # the winner down with it. Nothing wraps this today; keep it that way.
    nil
  end

  # The senior's own day, not the server's — the cap is about how often their
  # phone rings, and a UTC boundary would cut their evening in half.
  def self.local_day(user, now)
    zone = ActiveSupport::TimeZone[user.tz.to_s] || Time.zone
    now.in_time_zone(zone).to_date
  end

  # The lowest slot nobody holds, or nil when the day is spent.
  #
  # A slot is released — daily_sequence set to NULL — when an attempt turns out
  # never to have rung: cancelled because she resolved it herself or the sweep
  # closed it, failed because the provider was never reached. Ten failures early
  # in the day must not silence every later reminder once the integration
  # recovers, and the per-occurrence MAX_ATTEMPTS and RETRY_AFTER already bound a
  # runaway failure loop. This bounds a ringing telephone, not an API.
  def self.free_slot(user, day)
    taken = where(user_id: user.id, call_day: day).where.not(daily_sequence: nil).pluck(:daily_sequence)

    (1..MAX_CALLS_PER_DAY).find { |slot| taken.exclude?(slot) }
  end

  def self.zone_name(user)
    (ActiveSupport::TimeZone[user.tz.to_s] || Time.zone).name
  end

  def self.slots_used(user, day)
    where(user_id: user.id, call_day: day).where.not(daily_sequence: nil).count
  end

  # Slots taken recently under a *different* zone than the one now in force —
  # which is to say, calls the senior received before their clock was moved.
  # Zero in normal operation, because the zone is the same one.
  def self.slots_under_other_zones(user, current_zone, now)
    where(user_id: user.id, created_at: (now - 1.day)..now)
      .where.not(daily_sequence: nil)
      .where.not(call_tz: current_zone)
      .count
  end

  # How long an attempt may stay unfinished before we stop believing it is a
  # live call. Longer than any reminder call should last, short enough that a
  # row abandoned by a dead worker cannot block the line for the rest of the day.
  IN_FLIGHT_WINDOW = 5.minutes

  # An attempt that is dialling, ringing or talking right now. Released
  # attempts are excluded by the daily_sequence check: they never rang, so they
  # are not occupying the line.
  def self.call_in_flight?(user, now)
    where(user_id: user.id, completed_at: nil)
      .where.not(daily_sequence: nil)
      .where(created_at: (now - IN_FLIGHT_WINDOW)..now)
      .exists?
  end

  # Releases this attempt's hold on the day, for an attempt that never rang.
  def release_slot!(**attributes)
    update!(attributes.merge(daily_sequence: nil))
  end
end
