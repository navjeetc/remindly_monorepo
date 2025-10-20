if Rails.env.development?
  puts "Creating seed data..."
  
  # Create admin user
  admin = User.find_or_create_by!(email: "navjeet@anakhsoft.com") do |u|
    u.role = :admin
    u.tz = "America/New_York"
  end
  puts "✓ Created admin: #{admin.email}"
  
  # Create test users with roles
  senior = User.find_or_create_by!(email: "senior@example.com") do |u|
    u.role = :senior
    u.tz = "America/New_York"
  end
  caregiver = User.find_or_create_by!(email: "caregiver@example.com") do |u|
    u.role = :caregiver
    u.tz = "America/New_York"
  end
  
  # Create a user without role (pending approval)
  pending = User.find_or_create_by!(email: "pending@example.com") do |u|
    u.role = nil
    u.tz = "America/New_York"
  end
  
  puts "✓ Created users: #{User.count}"
  puts "  - Admin: navjeet@anakhsoft.com"
  puts "  - Senior: senior@example.com"
  puts "  - Caregiver: caregiver@example.com"
  puts "  - Pending: pending@example.com (no role)"
  
  # Create caregiver link
  link = CaregiverLink.find_or_create_by!(senior: senior, caregiver: caregiver) do |l|
    l.status = :active
  end
  puts "✓ Linked caregiver to senior"
  
  # Create sample tasks
  Task.find_or_create_by!(
    senior: senior,
    created_by: caregiver,
    title: "Doctor Appointment",
    scheduled_at: 2.days.from_now.change(hour: 14, min: 0)
  ) do |t|
    t.task_type = :appointment
    t.priority = :high
    t.duration_minutes = 60
    t.location = "Main St Clinic, 123 Main St"
    t.description = "Annual checkup with Dr. Smith"
    t.notes = "Bring insurance card and medication list"
    t.assigned_to = caregiver
    t.status = :assigned
  end
  
  Task.find_or_create_by!(
    senior: senior,
    created_by: caregiver,
    title: "Grocery Shopping",
    scheduled_at: 1.day.from_now.change(hour: 10, min: 0)
  ) do |t|
    t.task_type = :errand
    t.priority = :medium
    t.duration_minutes = 90
    t.location = "Whole Foods Market"
    t.description = "Weekly grocery shopping"
    t.notes = "Get milk, bread, eggs, and vegetables"
    t.status = :pending
  end
  
  Task.find_or_create_by!(
    senior: senior,
    created_by: caregiver,
    title: "Pharmacy Pickup",
    scheduled_at: Time.current + 4.hours
  ) do |t|
    t.task_type = :errand
    t.priority = :urgent
    t.duration_minutes = 30
    t.location = "CVS Pharmacy"
    t.description = "Pick up prescription refill"
    t.assigned_to = caregiver
    t.status = :in_progress
  end
  
  Task.find_or_create_by!(
    senior: senior,
    created_by: caregiver,
    title: "Exercise Class",
    scheduled_at: 3.days.from_now.change(hour: 11, min: 0)
  ) do |t|
    t.task_type = :activity
    t.priority = :low
    t.duration_minutes = 45
    t.location = "Community Center"
    t.description = "Weekly senior fitness class"
    t.status = :pending
  end
  
  puts "✓ Created #{Task.count} sample tasks"
  
  # Add comments to tasks
  doctor_task = Task.find_by(title: "Doctor Appointment")
  if doctor_task
    TaskComment.find_or_create_by!(
      task: doctor_task,
      user: caregiver,
      content: "Don't forget to ask about blood pressure medication"
    )
    puts "✓ Added task comments"
  end
  
  # Add caregiver availability
  CaregiverAvailability.find_or_create_by!(
    caregiver: caregiver,
    date: Date.current
  ) do |a|
    a.start_time = Time.parse('09:00')
    a.end_time = Time.parse('17:00')
    a.notes = "Available all day"
  end
  
  CaregiverAvailability.find_or_create_by!(
    caregiver: caregiver,
    date: Date.tomorrow
  ) do |a|
    a.start_time = Time.parse('09:00')
    a.end_time = Time.parse('13:00')
    a.notes = "Morning only"
  end
  
  puts "✓ Created #{CaregiverAvailability.count} availability entries"
  puts "\n✅ Seed data complete!"
end
