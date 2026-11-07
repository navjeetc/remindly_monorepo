class Reminder < ApplicationRecord
  # Time-critical: a dose where being late matters as much as being missed.
  #
  # A caregiver reviewing Remindly asked for this after describing Parkinson's
  # medication, where the window is narrow enough that the gap between "did not
  # answer" and "somebody was told" is the thing that matters.
  #
  # For an ordinary reminder that gap is fifty minutes: the calls give up after
  # three attempts five minutes apart, and MarkMissedOccurrencesJob waits a full
  # hour before telling anybody. Marking a reminder critical is what closes it —
  # caregivers hear about a minute after a call goes unanswered instead.
  #
  # Marked on the reminder rather than derived from the category, because
  # "medication" covers a vitamin as well as a dose that cannot slip, and only
  # the person setting it up knows which this is.
  belongs_to :user
  has_many :occurrences, dependent: :destroy
  enum :category, { medication: 0, hydration: 1, routine: 2 }, prefix: true
  validates :title, :rrule, :tz, presence: true

  # A reminder is kept in the clock of the person it is for, always.
  #
  # tz used to be whatever the caller supplied — RemindersController permits it
  # in reminder_params — so a caregiver whose own device said New Delhi created
  # New York seniors' reminders stamped "New Delhi". Nothing corrected it
  # afterwards, and Recurrence expands the schedule in this column, so those
  # reminders were pinned to a zone that has never observed daylight saving:
  # every spring and autumn the senior's clock moved and the reminder did not.
  # Two on the production account had drifted an hour by the time anybody
  # noticed, and one had drifted out of the 8am-9pm calling window entirely,
  # which would have silently stopped it ever telephoning.
  #
  # Set here rather than in each controller because there are three ways in —
  # the dashboard, the JSON API and the console — and only one of them was
  # getting it right. A denormalised copy that cannot disagree with its source
  # is worth having; one that can is exactly this bug.
  before_validation :keep_the_clock_of_the_person_it_is_for

  # The free plan rings a parent for at most three reminders on any one day.
  # Checked when a reminder is set up or changed, never when it is due: the
  # fourth is refused here, with the way to keep it on the screen only, so a
  # call already on the schedule is never the one that loses. Retries and the
  # snooze call-back belong to a reminder already counted, so they never count.
  validate :within_the_plans_phone_reminders, if: :counts_against_the_call_allowance?

  scope :ringing, -> { where(phone_call: true) }

  WEEKDAYS = %w[SU MO TU WE TH FR SA].freeze

  # The days of the week this reminder can ring on: one for a weekly reminder,
  # all seven otherwise. Generous rather than exact for anything the dashboard
  # cannot create (a monthly rule from the API counts every day), because the
  # cost of overcounting is a refused reminder with a plain reason, and the
  # cost of undercounting is a limit that does not hold.
  def call_days
    return (0..6).to_a unless rrule.to_s.include?("FREQ=WEEKLY")

    listed = rrule[/BYDAY=([A-Z,]+)/, 1]
    return listed.split(",").filter_map { |day| WEEKDAYS.index(day) } if listed

    [ (start_time || Time.current).in_time_zone(tz.presence || "UTC").wday ]
  end

  private

  # Not on a change of time alone: moving a reminder from 8:00 to 9:00 rings no
  # more often, and a family over the limit after a downgrade can still adjust
  # what they have.
  def counts_against_the_call_allowance?
    phone_call? && user.present? &&
      (new_record? || will_save_change_to_phone_call? || will_save_change_to_rrule?)
  end

  def within_the_plans_phone_reminders
    plan = user.care_plan
    limit = plan.phone_reminders_a_day
    return if limit.nil?

    others = user.reminders.ringing.where.not(id: id).to_a
    busiest = call_days.map { |day| others.count { |r| r.call_days.include?(day) } }.max.to_i
    return if busiest < limit

    errors.add(:base, "#{user.display_name} already has #{limit} phone reminders on some days, which is as many " \
                      "as the #{plan.name} plan rings. Untick \"Ring their phone\" to keep this one on the screen " \
                      "only. #{Plan.upgrade_hint}")
  end

  def keep_the_clock_of_the_person_it_is_for
    self.tz = user.tz if user&.tz.present?
  end
end
