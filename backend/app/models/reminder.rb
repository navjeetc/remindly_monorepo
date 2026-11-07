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
  # snooze call-back belong to a time already counted, so they never count.
  validate :within_the_plans_phone_reminders, if: :adds_calls?

  scope :ringing, -> { where(phone_call: true) }

  WEEKDAYS = %w[SU MO TU WE TH FR SA].freeze

  # How many times a rule rings on each day of the week, Sunday first.
  #
  # Counted in scheduled times, not reminders: one rule can ring many times a
  # day (FREQ=HOURLY, or a BYHOUR list, both accepted by the API), and counting
  # it once would let a single reminder through the allowance. (Codex and
  # Copilot on #226.)
  #
  # Generous rather than exact for rules the dashboard cannot write: a monthly
  # rule counts on every day. Overcounting costs a refused reminder with a plain
  # reason; undercounting costs a limit that does not hold.
  def self.calls_by_day(rrule, start_time, tz)
    rule = rrule.to_s
    a_day = times_a_day(rule)
    days = ringing_days(rule, start_time, tz)
    (0..6).map { |day| days.include?(day) ? a_day : 0 }
  end

  def self.times_a_day(rule)
    interval = [ rule[/INTERVAL=(\d+)/, 1].to_i, 1 ].max
    case rule[/FREQ=([A-Z]+)/, 1]
    when "SECONDLY" then (86_400.0 / interval).ceil
    when "MINUTELY" then (1_440.0 / interval).ceil
    when "HOURLY"   then (24.0 / interval).ceil
    else
      [ rule[/BYHOUR=([\d,]+)/, 1], rule[/BYMINUTE=([\d,]+)/, 1] ]
        .map { |list| list ? list.split(",").size : 1 }
        .reduce(:*)
    end
  end

  def self.ringing_days(rule, start_time, tz)
    listed = rule[/BYDAY=([A-Z0-9,+-]+)/, 1]
    return listed.split(",").filter_map { |day| WEEKDAYS.index(day[-2, 2]) } if listed
    return (0..6).to_a unless rule.include?("FREQ=WEEKLY")

    # A weekly rule with no BYDAY rings on the weekday it starts, so moving
    # start_time can move it to another day.
    [ (start_time || Time.current).in_time_zone(tz.presence || "UTC").wday ]
  end

  def calls_by_day
    phone_call? ? self.class.calls_by_day(rrule, start_time, tz) : Array.new(7, 0)
  end

  private

  def calls_by_day_before
    return Array.new(7, 0) if new_record? || !phone_call_in_database

    self.class.calls_by_day(rrule_in_database, start_time_in_database, tz_in_database)
  end

  # Checked only when a change makes some day ring more: a new reminder, the
  # box ticked again, a weekly reminder moved to another day, a second time
  # added. Not when the clock moves (8:00 to 9:00, or BYHOUR=9 to BYHOUR=10),
  # so a family over the limit after a downgrade can still adjust what they
  # have. (Codex and Copilot on #226.)
  def adds_calls?
    return false unless phone_call? && user.present?

    before = calls_by_day_before
    calls_by_day.each_with_index.any? { |count, day| count > before[day] }
  end

  def within_the_plans_phone_reminders
    plan = user.care_plan
    limit = plan.phone_reminders_a_day
    return if limit.nil?

    mine = calls_by_day
    before = calls_by_day_before
    others = user.reminders.ringing.where.not(id: id).map(&:calls_by_day).transpose.map(&:sum)
    others = Array.new(7, 0) if others.empty?

    over = (0..6).any? { |day| mine[day] > before[day] && others[day] + mine[day] > limit }
    return unless over

    errors.add(:base, "#{user.display_name} can have #{limit} phone reminders a day on the #{plan.name} plan, " \
                      "and this would make more on some days. Untick \"Ring their phone\" to keep this one on " \
                      "the screen only. #{Plan.upgrade_hint}")
  end

  def keep_the_clock_of_the_person_it_is_for
    self.tz = user.tz if user&.tz.present?
  end
end
