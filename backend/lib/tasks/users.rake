namespace :users do
  desc "Populate user names from email addresses (first part before @)"
  task populate_names_from_email: :environment do
    puts "Populating user names from email addresses..."
    
    updated_count = 0
    User.find_each do |user|
      # Only update if name is blank
      if user.name.blank?
        # Extract first part of email (before @)
        email_name = user.email.split('@').first
        
        # Capitalize and replace common separators with spaces
        # e.g., "john.smith" -> "John Smith", "mary_jones" -> "Mary Jones"
        formatted_name = email_name
          .gsub(/[._-]/, ' ')  # Replace dots, underscores, dashes with spaces
          .split(' ')
          .map(&:capitalize)
          .join(' ')
        
        user.update(name: formatted_name)
        puts "  ✓ Updated #{user.email} -> #{formatted_name}"
        updated_count += 1
      else
        puts "  - Skipped #{user.email} (already has name: #{user.name})"
      end
    end
    
    puts "\n✅ Done! Updated #{updated_count} users."
  end
  
  desc "Clear all user names and nicknames"
  task clear_names: :environment do
    puts "Clearing all user names and nicknames..."
    
    User.update_all(name: nil, nickname: nil)
    
    puts "✅ Done! Cleared names for #{User.count} users."
  end
end
