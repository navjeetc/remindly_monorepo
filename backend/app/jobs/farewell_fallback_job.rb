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

  # The longest farewell is about eight seconds, measured on a live call. This is
  # long enough that the event path always wins when it works, and short enough
  # that a lost event costs somebody half a minute rather than an evening.
  WAIT = 30.seconds

  def perform(call_id)
    call = TelnyxCall.find_by(id: call_id)
    return unless call

    # The event path finished the job, which is the ordinary case.
    return if call.status == "hangup" || call.completed_at.present?

    # Tolerant, because this is tidying up after a call that has almost
    # certainly ended on its own by now, and a failure here must not retry
    # forever against a call nobody is on.
    TelnyxVoiceService.hangup(call_control_id: call.call_control_id) if call.call_control_id.present?

    # Stamped whatever the provider answered. The farewell's business is over,
    # and releasing the number is what matters: a row left claiming the line
    # blocks the next reminder to this person for as long as it stands.
    TelnyxCall.where(id: call.id, completed_at: nil)
              .update_all(completed_at: Time.current, updated_at: Time.current)
  end
end
