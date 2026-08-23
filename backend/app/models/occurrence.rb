class Occurrence < ApplicationRecord
  belongs_to :reminder
  has_many :acknowledgements, dependent: :destroy
  has_many :telnyx_calls, dependent: :destroy
  enum :status, { pending: 0, acknowledged: 1, missed: 2 }, prefix: true

  # Why the telephone never reached this person, or nil when that is not the
  # story. The caregiver email hangs off this, and the distinction is the whole
  # point: "she has not marked it as done" is a statement about her, and it is
  # false when nobody ever asked her.
  #
  #   :outside_calling_hours  no call was placed, and none legally could be
  #   :could_not_place        attempts were made and not one reached the provider
  #
  # nil means either a call genuinely went out — answered or not, which is an
  # ordinary miss and hers to explain — or the telephone is not her channel.
  #
  # A claimed attempt only counts as a call once it has a call_control_id. That
  # is the provider's receipt: without one, nothing was dialled, whatever the
  # attempt row says. Testing mere existence would let a reservation that failed
  # before the API call masquerade as a call that rang.
  #
  # Reads only what was recorded, never the senior's current preferences. A
  # senior who turns voice reminders off, or whose number is cleared, after a
  # call was suppressed or failed does not thereby become someone who ignored a
  # reminder — durable evidence of what happened outranks a mutable setting read
  # later, when the email is finally rendered. Nothing recorded yields nil,
  # which is the same answer the preference checks used to give.
  def phone_failure_reason
    return nil if telnyx_calls.where.not(call_control_id: nil).exists?

    # Cancelled attempts are excluded deliberately. Those were claimed and then
    # abandoned before the provider was contacted — because she resolved the
    # reminder herself, or the sweep closed it — so "we tried to call and could
    # not get through" would be untrue of them.
    return :could_not_place if telnyx_calls.where.not(status: "cancelled").exists?

    # The recorded decision beats any re-derivation. Asking
    # within_calling_hours?(at: scheduled_at) now would answer for the schedule
    # rather than for the moment the call was refused: an 8:59pm reminder whose
    # job ran at 9:01 was refused, but 8:59 is inside the window, so the senior
    # would be blamed for a call nobody placed.
    return call_suppressed_reason.to_sym if call_suppressed_at.present? && call_suppressed_reason.present?

    nil
  end

  # Written when a delivery attempt is refused before it becomes an attempt.
  # Idempotent: the first refusal is the one worth dating.
  # Idempotent: the first refusal is the one worth dating.
  #
  # A conditional UPDATE rather than check-then-write, following
  # User#mark_email_undeliverable! for the same reason. Two callers can reach
  # here for one occurrence — the scheduler refusing it for calling hours while
  # a delayed job finds it already swept to missed — and both would read a blank
  # timestamp before either wrote, so the later one would quietly replace the
  # first reason. The WHERE clause makes the database pick.
  def suppress_call!(reason, at: Time.current)
    claimed = self.class.where(id: id, call_suppressed_at: nil)
                  .update_all(call_suppressed_at: at, call_suppressed_reason: reason.to_s,
                              updated_at: Time.current)

    # Keep this instance honest either way: adopt our own values if we won, the
    # winner's if we did not.
    if claimed.positive?
      assign_attributes(call_suppressed_at: at, call_suppressed_reason: reason.to_s)
    else
      reload
    end

    clear_attribute_changes([ :call_suppressed_at, :call_suppressed_reason ])
    self
  end

  SNOOZE_DEFAULT_MINUTES = 10
  SNOOZE_MIN_MINUTES = 1

  # Snoozing is two facts, not one: this occurrence is resolved, and another one
  # is due later. Both things that can snooze -- the senior's web page and a
  # keypress on a reminder phone call -- need the pair, so it lives here rather
  # than in either controller. Recording only the acknowledgement would mark the
  # reminder handled and never bring it back.
  #
  # Snoozing must never move a reminder earlier. The senior UI shows Snooze
  # before the scheduled time, so "10 minutes from now" would reschedule a 10:25
  # reminder tapped at 10:00 to 10:10 -- 15 minutes *earlier* than it was already
  # going to arrive, which is the opposite of what the word means.
  #
  # A retry -- a lost response, a double tap, a webhook Telnyx sends twice --
  # must land on the same snoozed occurrence rather than creating another one or
  # failing. The snooze time is derived from the first snooze acknowledgement for
  # this occurrence, not from Time.current: measuring from "now" is only stable
  # before the scheduled time; once it has passed, every retry would compute a
  # later target and create another occurrence.
  #
  # Returns the newly scheduled occurrence.
  def snooze!(minutes: SNOOZE_DEFAULT_MINUTES)
    later = nil

    transaction do
      ack = acknowledgements.find_by(kind: :snooze) ||
            Acknowledgement.create!(occurrence: self, kind: "snooze", at: Time.current)

      # Whichever is later: the time it was due, or the moment it was snoozed.
      target = [ scheduled_at, ack.at ].max + minutes.minutes

      # Occurrences are unique on (reminder_id, scheduled_at), so the target may
      # already exist -- from a retry, or from an already-materialised
      # recurrence. find_or_create_by is a SELECT then an INSERT, so a
      # concurrent double tap can still lose the race; the rescue takes the row
      # the other request won.
      later = begin
        Occurrence.find_or_create_by!(reminder: reminder, scheduled_at: target) do |o|
          o.status = :pending
        end
      rescue ActiveRecord::RecordNotUnique
        Occurrence.find_by!(reminder: reminder, scheduled_at: target)
      end

      update!(status: :acknowledged)
    end

    later
  end
end
