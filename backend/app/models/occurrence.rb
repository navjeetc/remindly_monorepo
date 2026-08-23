class Occurrence < ApplicationRecord
  belongs_to :reminder
  has_many :acknowledgements, dependent: :destroy
  has_many :telnyx_calls, dependent: :destroy
  enum :status, { pending: 0, acknowledged: 1, missed: 2 }, prefix: true

  # True when the only reason nobody responded is that Remindly never asked: the
  # senior takes their reminders by phone, and this one fell outside the hours a
  # call may legally be placed, so no call went out at all.
  #
  # The caregiver email hangs off this. Telling someone their mother "has not
  # marked it as done" when her phone never rang reports a non-event as a
  # negative one, and a caregiver acting on that would go looking for a lapse
  # that never happened.
  #
  # Derived rather than stored, because every input is already recorded and the
  # answer has to be recomputed against the senior's *current* timezone anyway.
  # The telnyx_calls check is what keeps it honest: if a call did go out -- a
  # queue backlog delivering a 7:55 occurrence at 8:05, say -- then a real
  # attempt was made and this is an ordinary miss, whatever the scheduled hour
  # says in hindsight.
  def phone_call_withheld?
    senior = reminder.user

    return false unless senior.voice_reminders_enabled?
    return false if senior.phone.blank?
    return false if telnyx_calls.exists?

    !senior.within_calling_hours?(at: scheduled_at)
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
