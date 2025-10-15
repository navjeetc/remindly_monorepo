class MakeCaregiverIdOptionalInCaregiverLinks < ActiveRecord::Migration[8.0]
  def change
    change_column_null :caregiver_links, :caregiver_id, true
  end
end
