# frozen_string_literal: true

# The beta thank-you, done by the deploy rather than by hand afterwards. Paid
# plans start with this release (Plan::LAUNCHED_ON), and the entrypoint runs
# migrations before the new code serves a request or runs a job, so no account
# is ever on Free in between: during that gap a retry or an escalation call
# would have been refused and not put back. (Copilot on #229.)
#
# Every account that exists now gets Family until 2027-11-08 (a year from
# midnight New York time on launch day). Accounts created later on launch day
# are granted on creation (User::PlanLimits). Times are written out rather than
# read from Plan so this migration means the same thing whenever it runs.
class GrantTheBetaYear < ActiveRecord::Migration[8.1]
  GRANTED_UNTIL = "2027-11-08 05:00:00"

  def up
    execute <<~SQL
      UPDATE users
      SET family_granted_until = '#{GRANTED_UNTIL}', updated_at = CURRENT_TIMESTAMP
      WHERE family_granted_until IS NULL OR family_granted_until < '#{GRANTED_UNTIL}'
    SQL
  end

  def down
    # Not reversible in meaning: rolling back the code puts every account back
    # on Beta, which ignores this column anyway.
  end
end
