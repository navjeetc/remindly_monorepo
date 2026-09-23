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

    # Three steps, in this order, because two earlier orderings were each wrong
    # in a different direction.
    #
    # Hanging up first was wrong: an account activated during the wait could
    # have a perfectly legitimate reminder call terminated on its way to a
    # deletion that then did not happen. Hanging up last was wrong too: the
    # destroy cascades the call rows away, so a crash between the two statements
    # left a live handset with no durable record from which anything could close
    # it.
    #
    # So the deletion is authorised first, the line is closed while the rows
    # still exist, and the destroy runs last in a transaction of its own that
    # re-reads the state. A crash anywhere in between leaves the account
    # standing, which SweepRefusedAccountsJob picks up -- the one outcome that
    # is recoverable, unlike a line nothing can reach.
    #
    # The lock is not a claim of perfect atomicity: the activation path does not
    # take it, and SQLite has no row lock to take. It narrows a window that was
    # thirty seconds wide to one statement under the database's own write
    # serialisation.
    open_calls = senior.with_lock do
      next [] unless senior.reload.senior_links.where(state: :provisional).exists?

      calls_that_may_still_be_up(senior).pluck(:call_control_id).compact
    end

    close(open_calls)

    senior.with_lock do
      next unless senior.reload.senior_links.where(state: :provisional).exists?

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

  # How far back an opted-out call is still worth hanging up. Comfortably longer
  # than a farewell and shorter than anything that could be a different call.
  FAREWELL_WINDOW = 10.minutes

  private

    # completed_at alone is not enough to say a call has ended.
    #
    # opt_out! stamps completed_at and say_farewell clears it again for the
    # length of the goodbye. Between those two writes the row claims to be
    # finished while the line is still up -- and if the process dies in that gap,
    # or the redelivery never comes, nothing clears it again. Filtering on
    # completed_at: nil would then skip the one call that matters, delete the row
    # with the user, and leave the handset connected with nothing left to close
    # it.
    #
    # So a recent opted-out call is included whatever its stamp says. Hanging up
    # a call that has already ended costs one refused request; the other way
    # round costs somebody an open line.
    def calls_that_may_still_be_up(senior)
      senior.telnyx_calls
            .where(completed_at: nil)
            .or(senior.telnyx_calls.where(outcome: "opted_out", created_at: FAREWELL_WINDOW.ago..))
    end

    # Nothing may be left ringing on a number whose account has just vanished.
    #
    # The farewell is normally ended by call.speak.ended, which hangs up and
    # stamps the row. If that event is lost, or its hangup fails, the call can
    # still be live when this timer fires -- and destroying the user cascades to
    # its telnyx_calls, so nothing would be left to close the line with.
    #
    # The tolerant hangup is right here: it is tidying up after a call that has
    # almost certainly ended already, the rows are gone either way, and a
    # provider refusing one of these must not take the whole job down.
    def close(call_control_ids)
      call_control_ids.each do |id|
        TelnyxVoiceService.hangup(call_control_id: id)
      end
    end
end
