# Test script for feature flags
puts "=" * 50
puts "Testing Feature Flag System"
puts "=" * 50

# Test 1: Check default values
puts "\n1. Default Values:"
puts "   Native scheduling: #{FeatureFlag.enabled?(:native_scheduling)}"
puts "   External scheduling: #{FeatureFlag.enabled?(:external_scheduling)}"

# Test 2: Enable native scheduling
puts "\n2. Enable native scheduling:"
FeatureFlag.enable!(:native_scheduling)
puts "   Native scheduling: #{FeatureFlag.enabled?(:native_scheduling)}"

# Test 3: Disable it again
puts "\n3. Disable native scheduling:"
FeatureFlag.disable!(:native_scheduling)
puts "   Native scheduling: #{FeatureFlag.enabled?(:native_scheduling)}"

# Test 4: Check all features
puts "\n4. All features:"
FeatureFlag.all.each do |key, config|
  puts "   #{key}:"
  puts "     Name: #{config[:name]}"
  puts "     Enabled: #{config[:enabled]}"
end

puts "\n" + "=" * 50
puts "✅ Feature flag tests complete!"
puts "=" * 50
