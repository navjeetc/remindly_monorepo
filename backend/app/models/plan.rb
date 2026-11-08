# frozen_string_literal: true

# What an account may set up: how many parents, how many phone reminders a day,
# how many caregivers, how many tries at an unanswered call, and whether
# escalation calls are offered. A plain object, not a table, because the plans
# are a product decision that changes with a release, not data anyone edits.
#
# Before LAUNCHED_ON every account was on BETA, which limits nothing. Paid
# plans launched on November 8, 2026: every account that existed by the end of
# that day was given a year of Family (plans:grant_beta_family) and told so
# (plans:send_launch_notice), which keeps the beta's promise that nobody loses
# what they were using.
#
# Every limit is checked when something is set up, never when a call is due.
# A medication call already on the schedule is never dropped because a count
# was reached. The retry allowance is the one limit read at call time, and it
# only decides how many times an unanswered call is tried again, never whether
# the first call is made.
class Plan
  # The day the beta ended for everyone at once. Nil would put every account
  # back on BETA.
  LAUNCHED_ON = Date.new(2026, 11, 8)

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

    return FREE if user.nil?

    [ user.family_until, user.family_granted_until ].compact.any? { |until_| until_ > at } ? FAMILY : FREE
  end

  # The plan a care receiver's reminders and caregivers are held to: the best
  # of their own and that of anyone looking after them. A parent is on Family
  # if anyone in their circle pays for it, so a second caregiver on the free
  # plan never takes features away from a family somebody else is paying for.
  #
  # joining: a caregiver about to be linked, counted as though they already
  # were, so the question "may they join?" is asked of the circle they would
  # make.
  def self.for_care_receiver(senior, at: Time.current, joining: nil)
    return BETA if beta?

    people = [ senior, joining, *senior.senior_links.where.not(caregiver_id: nil).includes(:caregiver).map(&:caregiver) ]
    people.compact.any? { |person| self.for(person, at: at) == FAMILY } ? FAMILY : FREE
  end

  # Said wherever a limit refuses something, so the next step is the same
  # everywhere.
  def self.upgrade_hint
    # Neutral about where to go: care receivers and the API see this too, and
    # neither can reach the Plan page. (Copilot on #227.)
    "The Family plan raises this limit."
  end
end
