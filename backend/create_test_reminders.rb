# Create final test reminders - 2 minutes from now, 2 minutes apart
# Run with: rails runner create_final_test.rb

user = User.find_or_create_by!(email: 'dev@remindly.local') do |u|
  u.name = "Dev User"
  u.role = :senior
  u.tz = "America/New_York"
end

# DELETE everything
puts "🗑️  Deleting ALL reminders..."
user.reminders.destroy_all

# Calculate times
tz = ActiveSupport::TimeZone[user.tz]
now = tz.now
time1 = now + 2.minutes
time2 = now + 4.minutes  # 2 minutes after first one

puts "🕐 Current time: #{now.strftime('%I:%M:%S %p')}"
puts "⏰ First reminder: #{time1.strftime('%I:%M:%S %p')}"
puts "⏰ Second reminder: #{time2.strftime('%I:%M:%S %p')}"
puts "   (#{((time2 - time1) / 60).to_i} minutes apart)"
puts ""

# Create first reminder
reminder1 = Reminder.create!(
  user: user,
  title: "Take your morning vitamins",
  notes: "First reminder",
  category: "medication",
  rrule: "FREQ=DAILY;BYHOUR=#{time1.hour};BYMINUTE=#{time1.min}",
  tz: user.tz
)
Recurrence.expand(reminder1)
puts "✅ Created: #{reminder1.title} at #{time1.strftime('%I:%M %p')}"

# Create second reminder
reminder2 = Reminder.create!(
  user: user,
  title: "Drink a glass of water",
  notes: "Second reminder",
  category: "hydration",
  rrule: "FREQ=DAILY;BYHOUR=#{time2.hour};BYMINUTE=#{time2.min}",
  tz: user.tz
)
Recurrence.expand(reminder2)
puts "✅ Created: #{reminder2.title} at #{time2.strftime('%I:%M %p')}"

puts ""
puts "=" * 60
puts "🎯 Final test reminders:"
puts "   1️⃣  #{time1.strftime('%I:%M %p')} - #{reminder1.title}"
puts "   2️⃣  #{time2.strftime('%I:%M %p')} - #{reminder2.title}"
puts ""
puts "📱 Refresh Safari (click 🔄)"
puts "   Voice announcements will work perfectly!"
puts "=" * 60
