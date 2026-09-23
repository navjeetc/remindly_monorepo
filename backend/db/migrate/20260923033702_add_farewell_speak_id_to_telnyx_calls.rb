# What a call has said on its way out, so that a goodbye is spoken once and
# finishes once.
#
# farewell_requested_at is claimed before the farewell is issued. Telnyx
# redelivers events, and a second delivery of the keypress would otherwise issue
# the same speak again -- which the provider refuses, as it should, and that
# refusal read as a failed farewell and hung up on the one already playing.
#
# farewell_speak_id is the provider's name for that speech. The outcome is
# already settled by the time anything is spoken, so "the farewell finished"
# has to be told apart from "some other speech finished" by the speech itself.
class AddFarewellSpeakIdToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :farewell_requested_at, :datetime
    add_column :telnyx_calls, :farewell_speak_id, :string
  end
end
