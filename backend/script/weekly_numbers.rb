# Monday morning numbers.
#
#   bin/rails runner script/weekly_numbers.rb
#
# In production, from the repo root:
#
#   ssh navjeetc@161.35.104.56 "docker exec -i \
#     \$(docker ps -q --filter label=service=remindly-backend --filter label=role=web | head -1) \
#     bin/rails runner -" < backend/script/weekly_numbers.rb
#
# This is a script and not a feature on purpose. It measures whether anybody is
# using Remindly; it does not help anybody use it. The moment it wants a
# dashboard, a mailer or a job, it has stopped being worth its own weight.
#
# The funnel is the one that matters, because each step is a place a real
# caregiver has actually stopped:
#
#   signed up -> created someone -> that person opened it -> agreed
#             -> a reminder was written -> somebody pressed Done
#
# Kimberly Marmol reached "created someone" in November 2026 and stopped, for
# ten months, and nothing in the product noticed. These are the numbers that
# would have said so.
#
# Every draft of this script has flattered the product in a different way, and
# each is worth naming so the next one is not reinvented:
#
#   - counting acknowledgement *events* against a denominator of *people*,
#     which printed "somebody pressed Done — 400%"
#   - treating an outside address linked to Navjeet's own senior account as a
#     household, which dragged his four reminders into the funnel behind it
#   - deciding ownership from the care receiver's email, so a real outside
#     caregiver using the accountless flow — whose care receiver has no address
#     by design — was filed as internal and vanished from every count
#
# A metric that flatters is worse than no metric.

INTERNAL_DOMAINS = %w[example.com anakhsoft.com chabbewal.com].freeze

# Whether an account with an address is one of Navjeet's own. Only ever asked
# about accounts that have an address: a care receiver created through the
# accountless flow has none by design, and deciding from that emptiness is the
# bug that hid every real household using the current setup route.
def internal_address?(user)
  email = user.email.to_s.downcase
  return false if email.empty?
  return true if email.include?("navjeet")

  INTERNAL_DOMAINS.any? { |domain| email.end_with?("@#{domain}") }
end

# A care receiver belongs to whoever the link says, unless they are demonstrably
# one of Navjeet's own accounts. No address means no evidence against, so they
# count as the caregiver's — which is the whole point of the accountless flow.
def demo_senior?(senior) = internal_address?(senior)

def row(label, value, of: nil)
  share = of && of.positive? ? format("  (%d%%)", (value * 100.0 / of).round) : ""
  puts format("  %-36s %5d%s", label, value, share)
end

now = Time.current
week = now - 7.days

puts
puts "Remindly — #{now.strftime('%A %-d %B %Y')}"
puts "=" * 58

# --- Who is actually out there -------------------------------------------
#
# Outsiders are every caregiver whose own address is not Navjeet's, including
# those who have created nobody. Filtering them out by their care receivers
# would make the first funnel step permanently 100% and hide the drop-off
# between signing up and setting somebody up — which, on the evidence so far,
# is where people go.

caregivers = User.where(role: :caregiver).to_a
outsiders  = caregivers.reject { |u| internal_address?(u) }

# Their care receivers, minus Navjeet's own account looked at through somebody
# else's login. Those are demonstrations, and they arrive complete with his
# reminders and his acknowledgements.
theirs = outsiders.to_h { |cg| [ cg, cg.seniors.reject { |s| demo_senior?(s) } ] }
demo_only = theirs.count { |cg, seniors| seniors.empty? && cg.seniors.any? }

puts
puts "CAREGIVERS"
row "accounts", caregivers.size
row "not yours", outsiders.size
row "of those, only demoing your account", demo_only
# outsiders, not caregivers: counting Navjeet's own test accounts as new
# signups is the exact flattery this file's preamble warns about, and it
# reported four in a week when the honest number was nought.
row "signed up this week", outsiders.count { |u| u.created_at > week }

# --- The funnel ----------------------------------------------------------
#
# Every row counts the same thing: outside caregivers who reached that step, out
# of every outside caregiver. One unit, one denominator, all the way down.
#
# There is deliberately no "handed over a link" row. create_care_receiver mints
# the link inside the same transaction that creates the person, so such a row
# would be true the instant "created someone" was, and would report a handoff
# for a caregiver who closed the tab immediately afterwards. The first honest
# evidence that anything reached the care receiver is the link being opened.

def reached(households)
  households.count { |_cg, seniors| seniors.any? && yield(seniors.map(&:id)) }
end

created = theirs.count { |_cg, seniors| seniors.any? }

# Evidence the care receiver actually turned up, which arrives differently on
# the two routes. Accountless: the device link has been used. Pairing: they hold
# their own account, which they can only have got by signing up and signing in
# to generate the code — so the account itself is the evidence.
#
# Counting only the link made the funnel non-monotonic, reporting nought here
# above ones on every row beneath it: a drop-off that never happened, for
# households that had simply arrived the other way.
turned_up = reached(theirs) do |ids|
  ReminderLink.where(user_id: ids).where.not(last_used_at: nil).exists? ||
    User.where(id: ids).where.not(email: [ nil, "" ]).exists?
end
accepted = outsiders.count do |cg|
  cg.caregiver_links.any? { |l| l.state_active? && l.senior && !demo_senior?(l.senior) }
end
wrote = reached(theirs) { |ids| Reminder.where(user_id: ids).exists? }
# kind: :taken only. Acknowledgement also stores snooze and skip, and a snoozed
# dose is the opposite of the thing this row claims to count.
done = reached(theirs) do |ids|
  Acknowledgement.kind_taken.joins(occurrence: :reminder)
                 .where(reminders: { user_id: ids }).exists?
end

puts
puts "THE FUNNEL (outside caregivers, #{outsiders.size} of them)"
row "created someone",        created,  of: outsiders.size
row "the person turned up",   turned_up, of: outsiders.size
row "they agreed",            accepted, of: outsiders.size
row "a reminder was written", wrote,    of: outsiders.size
row "somebody pressed Done",  done,     of: outsiders.size

# --- Where people are stuck right now ------------------------------------
#
# People sitting in a state, not events, because each of these is somebody to
# write to today. Counted over live links only: a revoked row is kept so its
# last use stays readable, and counting that history would leave every replaced
# credential permanently stuck, one household appearing several times and
# sometimes in two rows at once.

households = theirs.values.flatten.uniq
ids = households.map(&:id)
all_links = ReminderLink.where(user_id: ids)
live_links = ReminderLink.live.where(user_id: ids)

no_reminder = households.reject { |s| s.reminders.exists? }

# Over every link they have ever held, not just the live one. Replacing a device
# revokes the used link and mints a fresh one — ReminderLink.mint refuses a
# second live link — so asking only the live row would report a household that
# has been listening for months as having never opened it.
with_link = User.where(id: all_links.select(:user_id))
ever_used = User.where(id: all_links.where.not(last_used_at: nil).select(:user_id))
never_opened = with_link.where.not(id: ever_used.select(:id))

quiet = User.where(id: live_links.where.not(last_used_at: nil)
                                 .where(last_used_at: ...(now - 3.days)).select(:user_id))

puts
puts "STUCK RIGHT NOW (people, not links)"
row "set up, no reminder written", no_reminder.size
puts "  — of those on a device link (#{with_link.count}):"
row "never opened it",        never_opened.count
row "went quiet 3+ days ago", quiet.count

# Their caregivers, not Navjeet — he is linked to several of these people and
# does not need telling to write to himself.
if (writeable = no_reminder.flat_map { |s| s.caregivers.reject { |c| internal_address?(c) } }
                           .map(&:email).uniq.compact_blank).any?
  puts
  puts "  who to write to:"
  writeable.each { |e| puts "    #{e}" }
end

# --- Is the thing that fires actually firing -----------------------------
#
# Distinguishes "nobody uses it" from "it is broken", which look identical from
# outside and need opposite responses. Calls are counted only when the provider
# accepted one: a row is reserved before dialling, so counting reservations
# would report calls placed during precisely the outage this section exists to
# reveal.

puts
puts "LAST 7 DAYS"
row "occurrences due", Occurrence.where(scheduled_at: week..now).count
row "marked done",     Acknowledgement.kind_taken.where(created_at: week..now).count
row "snoozed or skipped",
    Acknowledgement.where(created_at: week..now).where.not(kind: :taken).count
row "went missed",     Occurrence.where(scheduled_at: week..now, status: :missed).count
row "reminder calls placed",
    TelnyxCall.reminders.where(created_at: week..now).where.not(call_control_id: nil).count

puts
