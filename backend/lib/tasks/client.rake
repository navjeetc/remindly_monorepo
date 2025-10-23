namespace :client do
  desc "Sync web client from clients/web to public/client"
  task :sync do
    source_dir = Rails.root.join('..', 'clients', 'web')
    target_dir = Rails.root.join('public', 'client')
    
    puts "🔄 Syncing web client..."
    puts "   From: #{source_dir}"
    puts "   To: #{target_dir}"
    
    # Create target directory if it doesn't exist
    FileUtils.mkdir_p(target_dir)
    
    # Copy all files
    FileUtils.cp_r(Dir.glob("#{source_dir}/*"), target_dir, verbose: false)
    
    puts "✅ Web client synced successfully!"
    puts ""
    puts "📁 Files copied:"
    Dir.glob("#{target_dir}/*").each do |file|
      size = File.size(file) / 1024.0
      puts "   - #{File.basename(file)} (#{size.round(1)} KB)"
    end
  end
  
  desc "Open web client in browser"
  task :open do
    url = "http://localhost:5000/client"
    puts "🌐 Opening web client: #{url}"
    system("open #{url}")
  end
end
