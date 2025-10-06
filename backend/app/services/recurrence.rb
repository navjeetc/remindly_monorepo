class Recurrence
  def self.expand(reminder, horizon_hours: 24)
    tz   = ActiveSupport::TimeZone[reminder.tz]
    now  = tz.now
    stop = now + horizon_hours.hours
    rule = IceCube::Rule.from_ical(reminder.rrule)
    schedule = IceCube::Schedule.new(now)
    schedule.add_recurrence_rule(rule)
    schedule.occurrences_between(now, stop).each do |t|
      reminder.occurrences.find_or_create_by!(scheduled_at: t)
    end
  end
end
