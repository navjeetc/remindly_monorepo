# frozen_string_literal: true

# The questions the plan limits ask about a person, asked where something is
# being set up. See Plan for the limits themselves and why none of them is
# applied when a call is due.
module User::PlanLimits
  extend ActiveSupport::Concern

  included do
    # The caregiver this care receiver counts against on plans that limit how
    # many parents a caregiver sets up. See parents_set_up_count.
    belongs_to :set_up_by, class_name: "User", optional: true

    # Somebody who signs up on launch day, after the migration that granted
    # everyone else the beta year, joined during it too. (Copilot on #229.)
    before_create :grant_the_beta_year, if: :joined_during_the_beta?
  end

  # By when the account was made, or now if it is being made now.
  def joined_during_the_beta?
    cutoff = Plan.beta_year_cutoff
    cutoff.present? && family_granted_until.nil? && (created_at || Time.current) <= cutoff
  end

  def grant_the_beta_year
    self.family_granted_until = Plan.beta_year_until
  end

  # The plan this person pays for, or would: theirs as a caregiver, or as a care
  # receiver who set themselves up.
  def plan = Plan.for(self)

  # The plan this person's reminders and caregivers are held to, as a care
  # receiver: the best in their circle.
  def care_plan(joining: nil) = Plan.for_care_receiver(self, joining: joining)

  # Parents this caregiver set up and still looks after: those whose account
  # they created, or whose token they were first to redeem (users.set_up_by_id,
  # written when it happens). Being invited to help with somebody else's parent
  # does not count, because that parent is already the inviter's.
  def parents_set_up_count
    caregiver_links.joins(:senior).where(users: { set_up_by_id: id }).count
  end

  def parent_limit_reached?
    limit = plan.parents
    limit.present? && parents_set_up_count >= limit
  end

  def caregiver_count
    senior_links.where.not(caregiver_id: nil).count
  end

  # joining: the caregiver about to be added. Their plan counts, so a Family
  # caregiver can join a family that already has two caregivers on the free
  # plan. (Copilot on #226.)
  def caregiver_limit_reached?(joining: nil)
    limit = care_plan(joining: joining).caregivers
    limit.present? && caregiver_count >= limit
  end

  def parent_limit_message
    "On the #{plan.name} plan you can set up #{plan.parents} #{"parent".pluralize(plan.parents)}. #{Plan.upgrade_hint}"
  end

  def caregiver_limit_message(joining: nil)
    plan = care_plan(joining: joining)
    "#{display_name} already has #{plan.caregivers} caregivers, which is as many as the " \
      "#{plan.name} plan allows. #{Plan.upgrade_hint}"
  end
end
