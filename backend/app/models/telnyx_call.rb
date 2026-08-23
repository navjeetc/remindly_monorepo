class TelnyxCall < ApplicationRecord
  belongs_to :occurrence
  belongs_to :user

  validates :call_control_id, presence: true, uniqueness: true
  validates :status, presence: true
  validates :outcome, presence: true

  STATUSES = %w[
    pending
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
end
