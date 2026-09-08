# Monday morning numbers.
#
#   bin/rails runner script/weekly_numbers.rb
#
# In production, from the repo root:
#
#   ssh root@161.35.104.56 'docker exec $(docker ps -q --filter label=service=remindly-backend --filter label=role=web | head -1) bin/rails runner script/weekly_numbers.rb'
#
# This is a script and not a feature on purpose. It measures whether anybody is
# using Remindly; it does not help anybody use it. The moment it wants a
# dashboard, a mailer or a job, it has stopped being worth its own weight.
#
# The funnel below is the one that matters, because each step is a place a real
# caregiver has actually stopped:
#
#   signed up -> created someone -> handed over a link -> that link was opened
#             -> wrote a reminder -> somebody pressed Done
#
# Kimberly Marmol reached "handed over a link" in November 2026 and stopped, for
# ten months, and nothing in the product noticed. These are the numbers that
# would have said so.

ACCOUNTS = %w[example.com anakhsoft.com chabbewal.com].freeze

def mine?(user)
  email = user.email.to_s.downcase
  return true if email.empty? # accountless care receivers belong to whoever made them
  return true if email.include?("navjeet")

  ACCOUNTS.any? { |domain| email.end_with?("@#{domain}") }
end

def row(label, value, of: nil)
  share = of && of.positive? ? format("  (%d%%)", (value * 100.0 / of).round) : ""
  puts format("  %-34s %5d%s", label, value, share)
end

now = Time.current
week = now - 7.days

puts
puts "Remindly — #{now.strftime('%A %-d %B %Y')}"
puts "=" * 58

# --- Who is actually out there -------------------------------------------
#
# Split rather than totalled. A count that includes Navjeet's own test accounts
# has flattered every previous look at this and is the reason the real number
# was a surprise.

# A real household needs both halves to be somebody else's. An outside address
# linked to Navjeet's own senior account is a demo, not a user — and it drags
# his four reminders into the funnel behind it, which is exactly how a metric
# ends up reporting that the product is working.
caregivers = User.where(role: :caregiver).to_a
outsiders  = caregivers.reject { |u| mine?(u) }
                       .select { |cg| cg.seniors.any? { |s| !mine?(s) } }
demos      = caregivers.reject { |u| mine?(u) }.size - outsiders.size

puts
puts "CAREGIVERS"
row "accounts", caregivers.size
row "real households", outsiders.size
row "outside demos on your account", demos
row "signed up this week", caregivers.count { |u| u.created_at > week }

# --- The funnel ----------------------------------------------------------
#
# Every row counts the same thing: outside caregivers who have reached that
# step. Mixing units here is how a funnel starts reporting 400% — an earlier
# version counted acknowledgement *events* against a denominator of *people*.
# One unit, one denominator, all the way down.

def reached(caregivers)
  caregivers.count { |cg| yield(cg.seniors.reject { |s| mine?(s) }) }
end

created  = reached(outsiders) { |ss| ss.any? }
handed   = reached(outsiders) { |ss| ReminderLink.where(user_id: ss.map(&:id)).exists? }
opened   = reached(outsiders) { |ss| ReminderLink.where(user_id: ss.map(&:id)).where.not(last_used_at: nil).exists? }
accepted = outsiders.count { |cg| cg.caregiver_links.any? { |l| l.state_active? && !mine?(l.senior) } }
wrote    = reached(outsiders) { |ss| Reminder.where(user_id: ss.map(&:id)).exists? }
done     = reached(outsiders) do |ss|
  Acknowledgement.joins(occurrence: :reminder).where(reminders: { user_id: ss.map(&:id) }).exists?
end

puts
puts "THE FUNNEL (outside caregivers, #{outsiders.size} of them)"
row "created someone",       created,  of: outsiders.size
row "handed over a link",    handed,   of: outsiders.size
row "link was opened",       opened,   of: outsiders.size
row "the person accepted",   accepted, of: outsiders.size
row "wrote a reminder",      wrote,    of: outsiders.size
row "somebody pressed Done", done,     of: outsiders.size

# --- Where people are stuck right now ------------------------------------
#
# Not a count of events but of people sitting in a state, which is the thing
# worth acting on. Each of these is somebody you could email today.

all_seniors = outsiders.flat_map { |cg| cg.seniors.reject { |s| mine?(s) } }.uniq
device_links = ReminderLink.where(user_id: all_seniors.map(&:id))

stalled_no_reminder = all_seniors.reject { |s| s.reminders.exists? }
never_opened = device_links.where(last_used_at: nil)
quiet = device_links.where.not(last_used_at: nil).where(last_used_at: ...(now - 3.days))

puts
puts "STUCK RIGHT NOW"
row "set up, no reminder written", stalled_no_reminder.size
row "link never opened",           never_opened.count
row "device quiet 3+ days",        quiet.count

if (names = stalled_no_reminder.map { |s| s.caregivers.map(&:email) }.flatten.uniq.compact_blank).any?
  puts
  puts "  who to write to:"
  names.each { |e| puts "    #{e}" }
end

# --- Is the thing that fires actually firing -----------------------------
#
# Distinguishes "nobody uses it" from "it is broken", which look identical from
# the outside and need opposite responses.

puts
puts "LAST 7 DAYS"
row "occurrences due",   Occurrence.where(scheduled_at: week..now).count
row "marked done",       Acknowledgement.where(created_at: week..now).count
row "went missed",       Occurrence.where(scheduled_at: week..now, status: :missed).count
row "calls placed",      TelnyxCall.where(created_at: week..now).count

puts
