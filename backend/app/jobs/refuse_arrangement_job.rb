# frozen_string_literal: true

# Deleting a provisional account after the call that refused it has ended.
#
# Pressing 9 on a setup call is a refusal of the whole arrangement when the
# account is provisional -- somebody whose only device is the telephone must be
# able to say no to an account another person made for them. That deletion used
# to happen inline, which was right while the webhook that recorded the refusal
# also hung up the call.
#
# It stopped being right when the call began saying goodbye first. Destroying the
# user cascades to its telnyx_calls, so the row vanishes mid-farewell and the
# call.speak.ended that was going to hang up cannot find it -- leaving somebody
# who has just refused connected to a line nothing will close.
#
# So the deletion waits. Not on the webhook, which may never arrive: on a clock,
# which cannot fail to. The wait only has to outlast a five-second farewell.
class RefuseArrangementJob < ApplicationJob
  queue_as :default

  # Long enough for the farewell and the hangup that follows it, short enough
  # that an account somebody has refused does not linger.
  DELAY = 30.seconds

  def perform(senior_id)
    senior = User.find_by(id: senior_id)
    return unless senior

    # Re-read rather than trusted from when this was enqueued. A caregiver can
    # activate a link in between, and an active account is not one a keypress
    # may delete: somebody already using Remindly who presses 9 is saying "stop
    # telephoning me", not "delete my account".
    return unless senior.senior_links.where(state: :provisional).exists?

    senior.destroy!
  rescue StandardError => e
    # Same swallow as the inline version this replaces. A failure here must not
    # retry forever against a row that cannot be destroyed, and the refusal
    # itself is already recorded: the calls are off either way.
    Rails.logger.error(
      "Refusing the arrangement failed for user #{senior_id}: #{e.class}: #{e.message}\n" \
      "#{Array(e.backtrace).first(5).join("\n")}"
    )
  end
end
