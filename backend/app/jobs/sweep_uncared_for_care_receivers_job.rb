# frozen_string_literal: true

# Care receivers who cannot sign in and have no caregiver left. See
# User::UNCARED_FOR_GRACE for why they exist and what happens to them.
#
# Two passes, nightly:
#
# 1. A backstop for the stamp. CaregiverLink keeps left_without_caregiver_at in
#    step as links change, but a link can also disappear without its callbacks
#    (delete_all, a crash between commit and callback), and accounts that were
#    already in this state when the column was added have no stamp at all. Any
#    of those is stamped now, which also switches their calls off.
#
# 2. Deletion once the grace period has passed. Each account is re-read inside
#    the transaction that deletes it: a caregiver who came back in the meantime
#    means it is kept, not deleted on the strength of a stale read.
class SweepUncaredForCareReceiversJob < ApplicationJob
  queue_as :default

  def perform(now: Time.current)
    User.without_a_caregiver.where(left_without_caregiver_at: nil).find_each(&:settle_caregiver_state!)

    User.role_senior.where(left_without_caregiver_at: ..(now - User::UNCARED_FOR_GRACE)).find_each do |senior|
      delete_if_still_uncared_for(senior, now)
    end
  end

  private

  def delete_if_still_uncared_for(senior, now)
    deleted = User.transaction do
      senior.lock!
      senior.settle_caregiver_state!
      next false unless senior.without_a_caregiver?
      next false unless senior.left_without_caregiver_at <= now - User::UNCARED_FOR_GRACE

      senior.destroy!
      true
    end

    Rails.logger.info("Deleted care receiver #{senior.id}: no caregiver since #{senior.left_without_caregiver_at.iso8601}") if deleted
  end
end
