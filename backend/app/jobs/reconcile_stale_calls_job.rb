# Closes call claims that have stopped mattering, out of the request path.
#
# Reconciliation asks the provider whether an old call is still connected, and
# may then hang it up and ask again — up to three round trips, each with its own
# timeout. That is fine inside VoiceReminderJob, where nobody is waiting, and not
# fine inside a caregiver's web request, where enough simultaneous verifications
# during a provider slowdown would occupy the whole web pool.
#
# So the controller enqueues this and tells the caregiver to try again in a
# moment. The claim is released a second later by a worker rather than held open
# by a browser.
class ReconcileStaleCallsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.phone.present?

    TelnyxCall.expire_stale_attempts(user, Time.current)
  end
end
