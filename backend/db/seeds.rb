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
end
