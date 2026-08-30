# frozen_string_literal: true

class AddNotifyOnCoverageGapsToUsers < ActiveRecord::Migration[8.1]
  # Opt-out (defaults on) so existing behavior is unchanged: caregivers still get
  # coverage-gap alerts unless they turn them off.
  def change
    add_column :users, :notify_on_coverage_gaps, :boolean, default: true, null: false
  end
end
