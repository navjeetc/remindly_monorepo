class Recurrence
  def self.expand(reminder, horizon_hours: 24)
    # The reminder's stamp, then the senior's clock, then the server's.
    #
    # The stamp comes first deliberately, even though the senior's clock is the
    # thing it is meant to equal. Reminder now keeps them equal on every write
    # and the repair migration fixes the rows written before that, so preferring
    # the stamp costs nothing — and preferring the *user* has a cost that is not
    # obvious: a senior editing their profile timezone would leave every reminder
    # stamped with the old zone, and the next dashboard load would expand in the
    # new one without removing what the old one had already materialised. A daily
    # 9am dose would gain a second row an hour away, and with phone reminders on
    # that is two calls for one tablet.
    #
    # Deciding what should happen when somebody moves — does 9am follow them, or
    # stay put? — is a real question and not this change's to answer. Keeping the
    # stamp first means this change does not answer it by accident.
    #
    # The fallbacks are the safety this method lacked: the naive lookup returned
    # nil for a zone that does not resolve and raised NoMethodError on the next
    # line, taking down whichever request touched that reminder first.
    tz   = ActiveSupport::TimeZone[reminder.tz.to_s] ||
           ActiveSupport::TimeZone[reminder.user&.tz.to_s] ||
           Time.zone
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

    today_start = now.beginning_of_day

    # Decide which occurrences to materialize.
    #
    # Always create current/upcoming occurrences (>= now). For occurrences whose
    # time has already passed *today*, create only the most recent one — the
    # "current" period. This keeps a same-day reminder visible even after its
    # clock time has passed (e.g. a caregiver in EST sets a reminder that is
    # already in the past for a senior in IST) without backfilling every earlier
    # slot of the day. Without this, an hourly / BYHOUR reminder opened for the
    # first time in the afternoon would spawn a pending occurrence for every
    # earlier hour, nagging the senior with stale reminders.
    upcoming, past = all_occurrences.partition { |t| t >= now }
    most_recent_past = past.select { |t| t >= today_start }.max
    to_create = upcoming
    to_create << most_recent_past if most_recent_past

    all_occurrences.each_with_index do |t, idx|
      Rails.logger.info "  [#{idx}] #{t} (#{to_create.include?(t) ? 'WILL CREATE' : 'SKIP'})"
    end

    to_create.sort.each do |t|
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

  def self.expand_task(task, horizon_days: 30)
    return unless task.rrule.present?

    # Fallback: task.tz -> senior.tz -> Time.zone (app default)
    tz = ActiveSupport::TimeZone[task.tz] ||
         ActiveSupport::TimeZone[task.senior.tz] ||
         Time.zone
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
      end
    end
  end
end
