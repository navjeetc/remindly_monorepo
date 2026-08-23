# The zone the daily slot was filed under.
#
# call_day comes from users.tz, which the senior (or a caregiver editing their
# profile) can change. At 00:30 UTC, Tokyo and Los Angeles are on different
# dates, so switching between them hands back a whole fresh set of slots — which
# makes the cap configurable away, the one thing invariant 7 says it must not be.
#
# Recording the zone makes the anomaly detectable without punishing normal
# operation: when the zone has not changed, nothing extra counts.
class AddCallTzToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :call_tz, :string
  end
end
