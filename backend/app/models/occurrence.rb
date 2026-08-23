class Occurrence < ApplicationRecord
  belongs_to :reminder
  has_many :acknowledgements, dependent: :destroy
  enum :status, { pending: 0, acknowledged: 1, missed: 2 }, prefix: true

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
