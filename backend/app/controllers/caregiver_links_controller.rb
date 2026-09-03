class CaregiverLinksController < ApplicationController
  before_action :authenticate!

  # Generate a pairing token for the current user (senior)
  def generate_token
    link = current_user.generate_pairing_token
    render json: {
      token: link.pairing_token,
      expires_at: link.expires_at.iso8601
    }, status: :created
  end

  # Pair with a senior using a pairing token
  def pair
    token = params.require(:token)
    link = CaregiverLink.find_by(pairing_token: token)

    unless link
      render json: { error: "Invalid or expired pairing token" }, status: :unprocessable_entity
      return
    end

    if link.redeemable?
      link.pair_with(caregiver: current_user)
      render json: {
        message: "Successfully paired with #{link.senior.email}",
        senior: {
          id: link.senior.id,
          email: link.senior.email
        }
      }
    elsif link.expired?
      # Said plainly, and only to somebody holding the exact token: they can
      # already tell it was real, and "invalid" would send them looking for a
      # typo instead of asking for a new one.
      render json: { error: "This pairing token has expired. Ask them to generate a new one." },
             status: :unprocessable_entity
    else
      render json: { error: "Invalid or expired pairing token" }, status: :unprocessable_entity
    end
  end

  # List all seniors linked to current caregiver
  def index
    links = current_user.caregiver_links.includes(:senior).where.not(caregiver_id: nil)

    render json: links.map { |link|
      {
        id: link.id,
        senior: {
          id: link.senior.id,
          email: link.senior.email,
          tz: link.senior.tz
        },
        permission: link.permission,
        created_at: link.created_at
      }
    }
  end

  # Remove a caregiver link
  def destroy
    link = current_user.caregiver_links.find(params[:id])
    link.destroy!
    head :no_content
  end
end
