# The provider's id for the goodbye this call is currently speaking.
#
# A call ends when the farewell finishes, and "the farewell finished" has to be
# distinguishable from "some other speech finished". The outcome alone cannot
# say which: it is already settled by the time anything is spoken, so any
# speak.ended arriving afterwards looked like the farewell's and would hang up
# on it.
class AddFarewellSpeakIdToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :farewell_speak_id, :string
  end
end
