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
    return nil if calls_on(user, day) >= MAX_CALLS_PER_DAY

    create!(
      occurrence: occurrence,
      user: user,
      attempt_number: (previous&.attempt_number || 0) + 1,
      call_day: day,
      # Monotonic, taken from the highest number used rather than from the count
      # that decides the cap. A cancelled attempt keeps its number while giving
      # its allowance back, so counting would hand the same number out twice and
      # the index would refuse a call the senior is entitled to.
      daily_sequence: (where(user_id: user.id, call_day: day).maximum(:daily_sequence) || 0) + 1,
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

  # What the senior's allowance has actually been spent on: calls that reached
  # the provider, and reservations still in flight.
  #
  # Excluded are attempts where the phone demonstrably never rang — cancelled,
  # because she resolved the reminder herself or the sweep closed it, and failed,
  # because the provider was never successfully contacted. Counting those would
  # let ten failures early in the day silence every later reminder even after the
  # integration recovered, which is the opposite of a safety cap's purpose. The
  # per-occurrence MAX_ATTEMPTS and RETRY_AFTER already bound a runaway failure
  # loop; this bounds a ringing telephone.
  def self.calls_on(user, day)
    where(user_id: user.id, call_day: day)
      .where.not(status: [ "cancelled", "failed" ])
      .count
  end
end
