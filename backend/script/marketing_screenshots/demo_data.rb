# Demo data for the marketing screenshots.
#
# Deliberately fictional: the dev database has real email addresses in it, and
# these images go on a public page. Nothing here is anyone's actual data.
TZ = "America/New_York".freeze

senior = User.find_or_initialize_by(email: "margaret@example.com")
senior.update!(name: "Margaret Ellis", role: :senior, tz: TZ)

caregiver = User.find_or_initialize_by(email: "alex@example.com")
caregiver.update!(name: "Alex Ellis", role: :caregiver, tz: TZ)

link = CaregiverLink.find_or_initialize_by(senior: senior, caregiver: caregiver)
link.update!(permission: :manage)

senior.reminders.destroy_all
Task.where(senior: senior).destroy_all

zone = ActiveSupport::TimeZone[TZ]
today = zone.now.beginning_of_day

reminders = [
  [ "Take your morning medication", :medication, 8,  0,  "Two white tablets with breakfast" ],
  [ "Have a glass of water",        :hydration,  10, 30, nil ],
  [ "Short walk after lunch",       :routine,    13, 15, "Once around the block is plenty" ],
  [ "Take your afternoon tablets",  :medication, 14, 0,  "The blue one, with food" ],
  [ "Have a glass of water",        :hydration,  16, 0,  nil ],
  [ "Take your evening medication", :medication, 20, 0,  "Two white tablets before bed" ]
]

reminders.each do |title, category, hour, minute, notes|
  at = today.change(hour: hour, min: minute)

  reminder = senior.reminders.create!(
    title: title, notes: notes, category: category,
    tz: TZ, start_time: at, rrule: "FREQ=DAILY"
  )

  reminder.occurrences.create!(scheduled_at: at, status: :pending)
end

# Varied days and times — every task at the same hour reads as fake.
tasks = [
  [ "Collect repeat prescription",   :errand,      :high,   :pending,  0, 15, 30, "Pharmacy on the high street — ready after 2pm" ],
  [ "Cardiology appointment",        :appointment, :high,   :assigned, 1, 14, 30, "Dr. Osei, third floor. Bring the blood pressure diary." ],
  [ "Grocery delivery arriving",     :errand,      :medium, :assigned, 2, 16, 0,  "Between 4 and 6pm — someone needs to be in" ],
  [ "Change the bed linen",          :household,   :low,    :pending,  3, 11, 0,  nil ],
  [ "Ring about the boiler service", :household,   :medium, :completed, -1, 9, 45, "Booked for the 14th" ]
]

tasks.each do |title, type, priority, status, days_out, hour, minute, notes|
  Task.create!(
    senior: senior,
    created_by: caregiver,
    assigned_to: (caregiver if %i[assigned completed].include?(status)),
    title: title, task_type: type, priority: priority, status: status, notes: notes,
    scheduled_at: (today + days_out.days).change(hour: hour, min: minute),
    completed_at: (status == :completed ? 1.day.ago : nil),
    tz: TZ, visible_to_senior: true
  )
end

puts "senior=#{senior.id} caregiver=#{caregiver.id}"
puts "reminders=#{senior.reminders.count} tasks=#{Task.where(senior: senior).count}"
