class Recurrence
  def self.expand(reminder, horizon_hours: 24)
    tz   = ActiveSupport::TimeZone[reminder.tz]
    now  = tz.now
    stop = now + horizon_hours.hours
    
    Rails.logger.info "🔄 Expanding reminder #{reminder.id}: '#{reminder.title}'"
    Rails.logger.info "📅 RRULE: #{reminder.rrule}"
    Rails.logger.info "🕐 Now: #{now}, Stop: #{stop}"
    
    rule = IceCube::Rule.from_ical(reminder.rrule)
    
    # Determine the start time for the schedule
    if reminder.start_time.present?
      # Use the stored start_time (for hourly reminders)
      start_time = reminder.start_time.in_time_zone(tz)
      Rails.logger.info "⏰ Using stored start_time: #{start_time}"
    else
      # Start from beginning of today to properly respect BYHOUR/BYMINUTE in RRULE
      start_time = now.beginning_of_day
      Rails.logger.info "⏰ Using beginning_of_day: #{start_time}"
    end
    
    schedule = IceCube::Schedule.new(start_time)
    schedule.add_recurrence_rule(rule)
    
    # Find occurrences from start_time onwards
    all_occurrences = schedule.occurrences_between(start_time, stop)
    Rails.logger.info "📋 IceCube found #{all_occurrences.count} occurrences"
    
    all_occurrences.each_with_index do |t, idx|
      Rails.logger.info "  [#{idx}] #{t} (#{t >= now - 1.hour ? 'WILL CREATE' : 'SKIP - too old'})"
      # Only create if it's in the future or within the last hour (for today's reminders)
      if t >= now - 1.hour
        reminder.occurrences.find_or_create_by!(scheduled_at: t)
      end
    end
  end
end
