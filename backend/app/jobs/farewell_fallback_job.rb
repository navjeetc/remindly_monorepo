# frozen_string_literal: true

# Ends a call whose farewell never reported finishing.
#
# A call that says goodbye is held open until call.speak.ended arrives, and that
# event is now the only thing that ends it. It is also an event this integration
# never consumed before the farewell existed -- and a Telnyx connection can be
# configured to deliver only some event types, a delivery can be lost, and its
# hangup can fail after the retries run out. Any of those left the line open with
# nothing listening: the person hears silence until they put the phone down, and
# the row goes on claiming the number, so no further call to it can be placed
# until reconciliation happens to notice.
#
# So the farewell is never the only thing that can end the call. A clock can.
class FarewellFallbackJob < ApplicationJob
  queue_as :default

  # The provider could not confirm the call ended. Raised so the attempt is
  # retried rather than treated as done.
  class HangupUnconfirmed < StandardError; end

  # The longest farewell is about eight seconds, measured on a live call. This is
  # long enough that the event path always wins when it works, and short enough
  # that a lost event costs somebody half a minute rather than an evening.
  WAIT = 30.seconds

  # Retried on the same clock while the provider still says the call is up, or
  # cannot say. After that the claim is left standing on purpose: a number held
  # a little too long is closed by the stale-call reconciliation the next time
  # anything is reserved for it, while a number freed too early lets a second
  # call be dialled into a handset still connected to the first.
  retry_on HangupUnconfirmed, wait: WAIT, attempts: 5

  def perform(call_id)
    call = TelnyxCall.find_by(id: call_id)
    return unless call

    # The event path finished the job, which is the ordinary case.
    #
    # Read from the terminal status alone. completed_at is not evidence the call
    # ended: when another row already held this number's live claim, hold_line
    # could not clear it, so a farewell could be playing on a call whose row
    # still read as complete -- and skipping on that would leave it connected.
    # hangup! on a call that has in fact ended is harmless; it confirms and
    # returns.
    return if call.status == "hangup"

    # The raising hangup, and the number is released only once it succeeds.
    #
    # This used the tolerant one and stamped completed_at whatever came back, on
    # the view that freeing the number mattered most. It does not: the tolerant
    # hangup swallows a refusal, so a transient failure released the claim on a
    # call that was still connected, and the scheduler could dial a second call
    # into it. hangup! succeeds when the provider ends the call or confirms it
    # has already ended, and raises when it can tell neither -- which is the case
    # that has to be retried rather than assumed.
    if call.call_control_id.present?
      begin
        TelnyxVoiceService.hangup!(call_control_id: call.call_control_id)
      rescue RuntimeError => e
        raise HangupUnconfirmed, e.message
      end
    end

    TelnyxCall.where(id: call.id, completed_at: nil)
              .update_all(completed_at: Time.current, updated_at: Time.current)
  end
end
