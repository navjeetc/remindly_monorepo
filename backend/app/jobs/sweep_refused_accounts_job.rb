# frozen_string_literal: true

# The backstop for a refusal that never finished.
#
# Pressing 9 on a setup call deletes a provisional account, and everything that
# carries out that deletion can fail: the enqueue can fail on a busy queue, the
# worker can die mid-job, the destroy can raise. Each of those is swallowed
# rather than retried forever, which is right for the request that was handling
# somebody's telephone call and wrong as the last word on the matter -- the
# design promises that refusing ends the arrangement, and an account that
# outlives its own refusal is that promise quietly broken.
#
# Nothing here reads a queue or a flag. The refusal is already durable in the
# rows themselves: an opt-out stamp on a user whose only link is provisional
# says exactly "this person said no and the account is still here".
class SweepRefusedAccountsJob < ApplicationJob
  queue_as :default

  # Long enough that a refusal in progress is never swept out from under the
  # call that is still speaking its farewell.
  SETTLE = 1.hour

  def perform
    refused_accounts.find_each do |senior|
      RefuseArrangementJob.perform_now(senior.id)
    end
  end

  private

  def refused_accounts
    User.where.not(call_opted_out_at: nil)
        .where(call_opted_out_at: ..SETTLE.ago)
        .where(id: CaregiverLink.where(state: :provisional).select(:senior_id))
  end
end
