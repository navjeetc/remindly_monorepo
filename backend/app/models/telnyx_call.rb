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

    create!(
      occurrence: occurrence,
      user: user,
      attempt_number: (previous&.attempt_number || 0) + 1,
      status: "reserved",
      outcome: "pending"
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
