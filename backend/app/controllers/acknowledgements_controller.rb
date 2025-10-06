class AcknowledgementsController < ApplicationController
  before_action :authenticate!

  def create
    occ  = Occurrence.joins(:reminder).where(reminders: { user_id: current_user.id }).find(params.require(:occurrence_id))
    kind = params.require(:kind)
    Acknowledgement.create!(occurrence: occ, kind:, at: Time.current)
    occ.update!(status: :acknowledged)
    head :created
  end
end
