class AcknowledgementsController < WebController
  before_action :authenticate!

  def create
    occ  = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    kind = params.require(:kind)
    Acknowledgement.create!(occurrence: occ, kind:, at: Time.current)
    occ.update!(status: :acknowledged)
    head :created
  end

  def snooze
    occ = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    minutes = params.fetch(:minutes, 10).to_i # Default 10 minutes
    
    # Create acknowledgement for snooze tracking
    Acknowledgement.create!(occurrence: occ, kind: 'snooze', at: Time.current)
    
    # Create new occurrence for snoozed time
    new_occ = Occurrence.create!(
      reminder: occ.reminder,
      scheduled_at: minutes.minutes.from_now,
      status: :pending
    )
    
    # Mark original as acknowledged
    occ.update!(status: :acknowledged)
    
    render json: { 
      snoozed_occurrence_id: new_occ.id,
      scheduled_at: new_occ.scheduled_at,
      minutes: minutes
    }, status: :created
  end
end
