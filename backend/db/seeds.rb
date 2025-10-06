if Rails.env.development?
  puts "Creating seed data..."
  senior = User.find_or_create_by!(email: "senior@example.com") do |u|
    u.role = :senior
    u.tz = "America/New_York"
  end
  caregiver = User.find_or_create_by!(email: "caregiver@example.com") do |u|
    u.role = :caregiver
    u.tz = "America/New_York"
  end
  puts "✓ Created users: #{User.count}"
end
