# frozen_string_literal: true

# When a care receiver who cannot sign in (no email: their caregiver set them
# up) lost their last caregiver. From that moment nobody can change or stop
# their reminders, so their calls stop at once, and the account is deleted
# after User::UNCARED_FOR_GRACE.
#
# No backfill: SweepUncaredForCareReceiversJob stamps anyone already in that
# state on its first run, which starts their grace period from then.
class AddLeftWithoutCaregiverAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :left_without_caregiver_at, :datetime
  end
end
