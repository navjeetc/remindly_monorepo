# frozen_string_literal: true

# Quick script to check reminders and occurrences
# Run with: rails runner check_reminders.rb

user = User.find_by(email: 'dev@remindly.local')

if user.nil?
  puts "❌ User 'dev@remindly.local' not found!"
  exit 1
end

puts "👤 User: #{user.email} (ID: #{user.id})"
puts "   Timezone: #{user.tz}"
puts ""

# Check reminders
reminders = user.reminders
puts "📋 Total Reminders: #{reminders.count}"
reminders.each do |r|
  puts "   - #{r.title} (#{r.category})"
  puts "     RRULE: #{r.rrule}"
  puts "     Occurrences: #{r.occurrences.count} (#{r.occurrences.where(status: :pending).count} pending)"
end
puts ""

# Check today's occurrences
tz = ActiveSupport::TimeZone[user.tz]
today_start = tz.now.beginning_of_day
today_end = today_start.end_of_day

today_occurrences = Occurrence.joins(:reminder)
  .where(reminders: { user_id: user.id }, scheduled_at: today_start..today_end)
  .order(:scheduled_at)

puts "📅 Today's Occurrences: #{today_occurrences.count}"
today_occurrences.each do |occ|
  time_str = occ.scheduled_at.in_time_zone(user.tz).strftime('%I:%M %p')
  status_emoji = occ.status == 'pending' ? '⏰' : '✅'
  puts "   #{status_emoji} #{time_str}: #{occ.reminder.title} (#{occ.status})"
end

if today_occurrences.empty?
  puts "   ⚠️  No occurrences found for today!"
  puts "   This is why the web client shows no reminders."
end
