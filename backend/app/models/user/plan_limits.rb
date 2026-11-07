# frozen_string_literal: true

# The questions the plan limits ask about a person, asked where something is
# being set up. See Plan for the limits themselves and why none of them is
# applied when a call is due.
module User::PlanLimits
  extend ActiveSupport::Concern

  # The plan this person pays for, or would: theirs as a caregiver, or as a care
  # receiver who set themselves up.
  def plan = Plan.for(self)

  # The plan this person's reminders and caregivers are held to, as a care
  # receiver: the best in their circle.
  def care_plan = Plan.for_care_receiver(self)

  # Parents this caregiver set up: those they were the first caregiver for,
  # whether by creating the account or by redeeming the care receiver's own
  # token. Being invited to help with somebody else's parent does not count,
  # because that parent is already the inviter's.
  def parents_set_up_count
    caregiver_links.where(<<~SQL.squish).count
      NOT EXISTS (
        SELECT 1 FROM caregiver_links earlier
        WHERE earlier.senior_id = caregiver_links.senior_id
          AND earlier.caregiver_id IS NOT NULL
          AND earlier.id < caregiver_links.id
      )
    SQL
  end

  def parent_limit_reached?
    limit = plan.parents
    limit.present? && parents_set_up_count >= limit
  end

  def caregiver_count
    senior_links.where.not(caregiver_id: nil).count
  end

  def caregiver_limit_reached?
    limit = care_plan.caregivers
    limit.present? && caregiver_count >= limit
  end

  def parent_limit_message
    "On the #{plan.name} plan you can set up #{plan.parents} #{"parent".pluralize(plan.parents)}. #{Plan.upgrade_hint}"
  end

  def caregiver_limit_message
    "#{display_name} already has #{care_plan.caregivers} caregivers, which is as many as the " \
      "#{care_plan.name} plan allows. #{Plan.upgrade_hint}"
  end
end
