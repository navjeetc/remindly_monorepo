class AddScreeningEventIdToTelnyxCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :telnyx_calls, :screening_event_id, :string
  end
end
