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
        begin
          occurrence = reminder.occurrences.find_or_create_by!(scheduled_at: t)
          Rails.logger.info "    ✅ Occurrence id=#{occurrence.id} for #{t}"
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.warn "    ⚠️ Duplicate occurrence prevented for #{t}: #{e.message}"
          # Occurrence already exists, fetch it
          occurrence = reminder.occurrences.find_by!(scheduled_at: t)
          Rails.logger.info "    ✅ Found existing occurrence id=#{occurrence.id}"
        end
      end
    end
  end

  def self.expand_task(task, horizon_days: 30)
    return unless task.rrule.present?
    
    tz = ActiveSupport::TimeZone[task.tz]
    now = tz.now
    stop = now + horizon_days.days
    
    Rails.logger.info "🔄 Expanding recurring task #{task.id}: '#{task.title}'"
    Rails.logger.info "📅 RRULE: #{task.rrule}"
    Rails.logger.info "🕐 Now: #{now}, Stop: #{stop}"
    
    rule = IceCube::Rule.from_ical(task.rrule)
    
    if task.start_time.present?
      start_time = task.start_time.in_time_zone(tz)
      Rails.logger.info "⏰ Using stored start_time: #{start_time}"
    else
      start_time = now.beginning_of_day
      Rails.logger.info "⏰ Using beginning_of_day: #{start_time}"
    end
    
    schedule = IceCube::Schedule.new(start_time)
    schedule.add_recurrence_rule(rule)
    
    all_occurrences = schedule.occurrences_between(start_time, stop)
    Rails.logger.info "📋 IceCube found #{all_occurrences.count} occurrences"
    
    all_occurrences.each_with_index do |scheduled_at, idx|
      Rails.logger.info "  [#{idx}] #{scheduled_at} (#{scheduled_at >= now ? 'WILL CREATE' : 'SKIP - past'})"
      
      if scheduled_at >= now
        begin
          child_task = task.child_tasks.find_or_create_by!(scheduled_at: scheduled_at) do |t|
            t.senior = task.senior
            t.created_by = task.created_by
            t.assigned_to = task.assigned_to
            t.title = task.title
            t.description = task.description
            t.task_type = task.task_type
            t.priority = task.priority
            t.duration_minutes = task.duration_minutes
            t.location = task.location
            t.notes = task.notes
            t.visible_to_senior = task.visible_to_senior
            t.status = :pending
          end
          Rails.logger.info "    ✅ Task instance id=#{child_task.id} for #{scheduled_at}"
        rescue ActiveRecord::RecordNotUnique => e
          Rails.logger.warn "    ⚠️ Duplicate task prevented for #{scheduled_at}: #{e.message}"
          child_task = task.child_tasks.find_by!(scheduled_at: scheduled_at)
          Rails.logger.info "    ✅ Found existing task id=#{child_task.id}"
        end
      end
    end
  end
end
