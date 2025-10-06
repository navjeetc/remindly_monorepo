#!/bin/bash
set -e

echo "🚀 Setting up Remindly Rails Backend with SQLite"
echo "=================================================="
echo ""

cd /Users/navjeetc/dev/remindly_monorepo

# Step 1: Backup existing code
echo "Step 1: Backing up existing backend code..."
if [ -d "backend_partial" ]; then
    rm -rf backend_partial
fi
mv backend backend_partial
echo "  ✓ Backed up to backend_partial/"

# Step 2: Generate new Rails app
echo "Step 2: Generating new Rails 8 API app with SQLite..."
rails new backend --api --database=sqlite3 --skip-test

cd backend

# Step 3 & 4: Update Gemfile and install
echo "Step 3: Updating Gemfile..."
cat >> Gemfile << 'EOF'

# Remindly-specific gems
gem "jwt", "~> 2.7"
gem "rack-cors", "~> 2.0"
gem "ice_cube", "~> 0.16"

group :development, :test do
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
end
EOF

echo "Step 4: Installing dependencies..."
bundle install

# Step 5: Setup RSpec
echo "Step 5: Setting up RSpec..."
rails generate rspec:install

# Step 6: Copy existing code
echo "Step 6: Copying code..."
cp ../backend_partial/app/models/*.rb app/models/
cp ../backend_partial/app/controllers/*.rb app/controllers/
mkdir -p app/services
cp ../backend_partial/app/services/*.rb app/services/

# Step 7: Configure CORS
echo "Step 7: Configuring CORS..."
cat > config/initializers/cors.rb << 'EOF'
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "*", headers: :any, methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end
EOF

# Step 8: Update routes
echo "Step 8: Updating routes..."
cat > config/routes.rb << 'EOF'
Rails.application.routes.draw do
  get  "magic/request",      to: "magic#request_link"
  get  "magic/verify",       to: "magic#verify"
  get  "magic/dev_exchange", to: "magic#dev_exchange"
  resources :reminders, only: [:create] do
    collection do
      get :today
    end
  end
  resources :acknowledgements, only: [:create]
  get "up" => "rails/health#show", as: :rails_health_check
end
EOF

# Step 9: Create migrations
echo "Step 9: Creating migrations..."
cat > db/migrate/$(date +%Y%m%d%H%M%S)_create_users.rb << 'EOF'
class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.integer :role, default: 0, null: false
      t.string :tz, default: "America/New_York"
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
EOF

sleep 1

cat > db/migrate/$(date +%Y%m%d%H%M%S)_create_reminders.rb << 'EOF'
class CreateReminders < ActiveRecord::Migration[8.0]
  def change
    create_table :reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :notes
      t.string :rrule, null: false
      t.string :tz, null: false
      t.integer :category, default: 0
      t.timestamps
    end
  end
end
EOF

sleep 1

cat > db/migrate/$(date +%Y%m%d%H%M%S)_create_occurrences.rb << 'EOF'
class CreateOccurrences < ActiveRecord::Migration[8.0]
  def change
    create_table :occurrences do |t|
      t.references :reminder, null: false, foreign_key: true
      t.datetime :scheduled_at, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end
    add_index :occurrences, [:reminder_id, :scheduled_at], unique: true
  end
end
EOF

sleep 1

cat > db/migrate/$(date +%Y%m%d%H%M%S)_create_acknowledgements.rb << 'EOF'
class CreateAcknowledgements < ActiveRecord::Migration[8.0]
  def change
    create_table :acknowledgements do |t|
      t.references :occurrence, null: false, foreign_key: true
      t.integer :kind, null: false
      t.datetime :at, null: false
      t.timestamps
    end
  end
end
EOF

sleep 1

cat > db/migrate/$(date +%Y%m%d%H%M%S)_create_caregiver_links.rb << 'EOF'
class CreateCaregiverLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :caregiver_links do |t|
      t.integer :senior_id, null: false
      t.integer :caregiver_id, null: false
      t.timestamps
    end
    add_foreign_key :caregiver_links, :users, column: :senior_id
    add_foreign_key :caregiver_links, :users, column: :caregiver_id
    add_index :caregiver_links, [:senior_id, :caregiver_id], unique: true
  end
end
EOF

cat > db/seeds.rb << 'EOF'
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
EOF

echo "Running database setup..."
bin/rails db:create db:migrate db:seed

echo ""
echo "✅ Setup Complete! Start with: cd backend && bin/rails s"
