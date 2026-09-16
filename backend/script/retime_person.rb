# Move somebody to the timezone they are actually in, keeping the times their
# reminders were meant to happen at.
#
#   bin/rails runner script/retime_person.rb -- --email someone@example.com --to America/New_York
#   bin/rails runner script/retime_person.rb -- --id 42 --to America/New_York --apply
#
# In production, from the repo root:
#
#   ssh navjeetc@161.35.104.56 "docker exec -i \
#     \$(docker ps -q --filter label=service=remindly-backend --filter label=role=web | head -1) \
#     bin/rails runner - -- --id 42 --to America/New_York" < backend/script/retime_person.rb
#
# Dry run unless --apply is passed. It prints the before and after wall-clock
# time of every affected reminder; read that list before applying.
#
# ## Why this needs a script at all
#
# Because correcting the zone is not enough, and doing only that looks like it
# worked. Two separate things are wrong after somebody picks the wrong zone, and
# they have to be put right in order.
#
# `Reminder#tz` fixes itself: the model carries
# `before_validation :keep_the_clock_of_the_person_it_is_for`, so any save
# re-points it at the user's zone. But the callback fires on the *reminder*, so
# updating the user alone leaves every existing reminder stamped with the old
# zone until something touches it.
#
# `start_time` does not fix itself, and this is the part that bites. It is an
# absolute instant, not a wall-clock time. Re-stamping the zone re-expresses the
# same moment in new words: a reminder created as 1:45pm in Halifax is 16:45 UTC,
# and 16:45 UTC read in New York is 12:45pm. The row now says New York and still
# fires an hour early, which is the worst of both — the screen agrees with the
# caregiver and the telephone does not.
#
# So the wall clock has to be re-anchored deliberately: read the time of day the
# reminder was meant to happen at in the zone it was written in, then re-parse
# that same text in the corrected zone.
#
# ## What this does not decide
#
# Whether a zone change *should* carry the wall clock is #105, and the honest
# answer depends on something the database cannot see: a person who has moved to
# Halifax wants their 8am dose at 8am Halifax (the instant moves), and a person
# who was never in Halifax wants the instant corrected (the wall clock stays).
#
# This script is only for the second case — somebody picked the wrong zone and
# is being put back. It is deliberately a script rather than a button, because
# the operator knows which case this is and the application does not.
#
# Tasks are left alone on purpose. `Task#tz` has no such callback and the task
# form pins its own zone so a form agrees with itself; changing that is #105.

require "optparse"

options = { apply: false }
OptionParser.new do |opts|
  opts.on("--email EMAIL") { |v| options[:email] = v }
  opts.on("--id ID", Integer) { |v| options[:id] = v }
  opts.on("--to ZONE") { |v| options[:to] = v }
  opts.on("--apply") { options[:apply] = true }
end.parse!(ARGV)

abort "Give --email or --id" if options[:email].blank? && options[:id].blank?
abort "Give --to, an IANA zone such as America/New_York" if options[:to].blank?

target = ActiveSupport::TimeZone[options[:to]]
abort "#{options[:to]} is not a zone Rails can resolve" if target.nil?

person = options[:id] ? User.find_by(id: options[:id]) : User.find_by(email: options[:email])
abort "No such person" if person.nil?

was = person.tz
if was == target.tzinfo.name
  puts "#{person.display_name} is already on #{was}. Nothing to do."
  exit
end

from = ActiveSupport::TimeZone[was.to_s]
puts "#{person.display_name} (##{person.id}): #{was} -> #{target.tzinfo.name}"
puts "#{options[:apply] ? 'APPLYING' : 'DRY RUN — pass --apply to write'}"
puts

reminders = person.reminders.to_a

# The whole plan is computed before anything is written, so the dry run and the
# real run print the same list and the transaction below has no thinking left to
# do. Each entry is the reminder, the wall clock it was meant to happen at, and
# the instant that same wall clock becomes in the corrected zone.
plan = reminders.map do |reminder|
  # Read in the zone it was written in. Falls back to the person's old zone for
  # a row whose own tz no longer resolves, rather than silently reading it as UTC.
  old_zone = ActiveSupport::TimeZone[reminder.tz.to_s] || from || Time.zone
  wall = reminder.start_time.in_time_zone(old_zone)
  [ reminder, wall, target.parse(wall.strftime("%Y-%m-%d %H:%M:%S")) ]
end

if plan.empty?
  puts "No reminders."
else
  plan.each do |reminder, wall, moved|
    puts format("  %-28s %s %s  ->  %s %s",
                reminder.title.to_s.truncate(28),
                wall.strftime("%-l:%M%P"), wall.strftime("%Z"),
                moved.strftime("%-l:%M%P"), moved.strftime("%Z"))
  end
end

unless options[:apply]
  puts
  puts "Nothing written. Re-run with --apply once the list above is right."
  exit
end

# One transaction, and the person's zone moves first: Reminder's
# keep_the_clock_of_the_person_it_is_for reads user.tz on every save, so saving a
# reminder before this would re-stamp it with the zone being left behind.
ActiveRecord::Base.transaction do
  person.update!(tz: target.tzinfo.name)

  plan.each do |reminder, _wall, moved|
    reminder.start_time = moved
    reminder.save!
    reminder.occurrences.where(status: :pending).destroy_all
    Recurrence.expand(reminder.reload)
  end
end

puts
puts "Done. #{person.display_name} is on #{person.reload.tz}; " \
     "#{plan.size} reminder(s) re-anchored and re-expanded."
