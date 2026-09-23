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

    close_any_call_still_open(senior)

    # Checked again with the row held, because the check above and the delete
    # below are otherwise two decisions about a state that can change between
    # them: the thirty-second wait is thirty seconds in which a caregiver can
    # activate the link, and deleting an account that has just started being
    # used is the one mistake this job must not make.
    #
    # Not a claim of perfect atomicity -- the activation path does not take this
    # lock, and SQLite has no row locks to take. It closes the window to a
    # single statement under the database's own write serialisation, which is
    # the difference between a race that needs thirty seconds of bad luck and
    # one that needs microseconds of it.
    senior.with_lock do
      return unless senior.reload.senior_links.where(state: :provisional).exists?

      senior.destroy!
    end
  rescue StandardError => e
    # Same swallow as the inline version this replaces. A failure here must not
    # retry forever against a row that cannot be destroyed, and the refusal
    # itself is already recorded: the calls are off either way.
    Rails.logger.error(
      "Refusing the arrangement failed for user #{senior_id}: #{e.class}: #{e.message}\n" \
      "#{Array(e.backtrace).first(5).join("\n")}"
    )
  end

  private

    # Nothing may be left ringing on a number whose account is about to vanish.
    #
    # The farewell is normally ended by call.speak.ended, which hangs up and
    # stamps the row. If that event is lost, or its hangup fails, the call can
    # still be live when this timer fires -- and destroying the user cascades to
    # its telnyx_calls, so the row that could have closed the line goes with it
    # and later events arrive for a call nobody can find.
    #
    # So the line is closed here first, from the row, while the row still
    # exists. The tolerant hangup is right for this one: it is tidying up after
    # a call that has almost certainly ended already, and a failure must not
    # stop the refusal being honoured.
    def close_any_call_still_open(senior)
      senior.telnyx_calls.where(completed_at: nil).find_each do |call|
        TelnyxVoiceService.hangup(call_control_id: call.call_control_id) if call.call_control_id.present?
        call.update_columns(completed_at: Time.current, updated_at: Time.current)
      end
    end
end
