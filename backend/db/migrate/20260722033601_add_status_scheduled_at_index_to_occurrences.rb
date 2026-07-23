class AddStatusScheduledAtIndexToOccurrences < ActiveRecord::Migration[8.1]
  def change
    # MarkMissedOccurrencesJob runs every 15 minutes and selects pending
    # occurrences within a scheduled_at range (WHERE status = ? AND scheduled_at
    # BETWEEN ? AND ?). The existing indexes are keyed on reminder_id, so this
    # sweep would otherwise scan the whole table. status first (equality) then
    # scheduled_at (range) is the order that filter wants.
    add_index :occurrences, [ :status, :scheduled_at ]
  end
end
