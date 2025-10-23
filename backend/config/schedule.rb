# Use this file to easily define all of your cron jobs.
#
# Learn more: http://github.com/javan/whenever

# Set the environment
set :environment, ENV['RAILS_ENV'] || 'production'

# Set output to log file
set :output, "log/cron.log"

# Daily audit report - runs every day at 10 PM
# Note: Time is in server's local timezone. To use a specific timezone, set:
#   set :chronic_options, hours24: true
#   ENV['TZ'] = 'America/New_York'
# Or use explicit cron syntax: '0 22 * * *' (10 PM in 24-hour format)
every 1.day, at: '10:00 pm' do
  rake "audit:daily_report"
end

# Example: Run every Monday at 9 AM for weekly reports
# every :monday, at: '9:00 am' do
#   rake "audit:weekly_report"
# end
