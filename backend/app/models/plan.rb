# frozen_string_literal: true

# What an account may set up: how many parents, how many phone reminders a day,
# how many caregivers, how many tries at an unanswered call, and whether
# escalation calls are offered. A plain object, not a table, because the plans
# are a product decision that changes with a release, not data anyone edits.
#
# Remindly is in beta, and while it is every account is on BETA, which limits
# nothing: the site promises that nobody loses what they use today, and the
# free plan's limits are smaller than "everything". Paid plans start by setting
# LAUNCHED_ON, in the same release that sends the 60 days' notice and stamps
# every beta account with a year of Family (see the pricing plan doc).
#
# Every limit is checked when something is set up, never when a call is due.
# A medication call already on the schedule is never dropped because a count
# was reached. The retry allowance is the one limit read at call time, and it
# only decides how many times an unanswered call is tried again, never whether
# the first call is made.
class Plan
  # Nil while in beta. A date here ends the beta for everyone at once.
  LAUNCHED_ON = nil

  # nil means no limit.
  Limits = Data.define(:key, :name, :parents, :phone_reminders_a_day, :caregivers, :call_attempts, :escalation)

  BETA = Limits.new(key: :beta, name: "Beta", parents: nil, phone_reminders_a_day: nil,
                    caregivers: nil, call_attempts: TelnyxCall::MAX_ATTEMPTS, escalation: true)
  FREE = Limits.new(key: :free, name: "Free", parents: 1, phone_reminders_a_day: 3,
                    caregivers: 2, call_attempts: 2, escalation: false)
  # "Unlimited, fair use" calls: MAX_CALLS_PER_DAY is the fair-use ceiling,
  # and it is not a plan limit, it guards every account against a runaway.
  FAMILY = Limits.new(key: :family, name: "Family", parents: 3, phone_reminders_a_day: nil,
                      caregivers: 5, call_attempts: TelnyxCall::MAX_ATTEMPTS, escalation: true)

  def self.beta?
    LAUNCHED_ON.nil? || Date.current < LAUNCHED_ON
  end

  # The plan an account is on as the one paying: a caregiver's, or a care
  # receiver's who set themselves up.
  def self.for(user, at: Time.current)
    return BETA if beta?

    user&.family_until.present? && user.family_until > at ? FAMILY : FREE
  end

  # The plan a care receiver's reminders and caregivers are held to: the best
  # of their own and that of anyone looking after them. A parent is on Family
  # if anyone in their circle pays for it, so a second caregiver on the free
  # plan never takes features away from a family somebody else is paying for.
  def self.for_care_receiver(senior, at: Time.current)
    return BETA if beta?

    people = [ senior, *senior.senior_links.where.not(caregiver_id: nil).includes(:caregiver).map(&:caregiver) ]
    people.any? { |person| self.for(person, at: at) == FAMILY } ? FAMILY : FREE
  end

  # Said wherever a limit refuses something, so the next step is the same
  # everywhere. There is no upgrade page yet; payments are the next PR.
  def self.upgrade_hint
    "The Family plan raises this limit."
  end
end
