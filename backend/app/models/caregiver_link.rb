class CaregiverLink < ApplicationRecord
  belongs_to :senior, class_name: "User"
  belongs_to :caregiver, class_name: "User", optional: true
  
  enum :permission, { view: 0, manage: 1 }, prefix: true
  
  validates :pairing_token, uniqueness: true, allow_nil: true
  
  # Generate a unique pairing token for linking
  def self.generate_pairing_token(senior:)
    token = SecureRandom.urlsafe_base64(32)
    create!(
      senior: senior,
      pairing_token: token,
      permission: :view
    )
  end
  
  # Complete pairing with a caregiver
  def pair_with(caregiver:)
    update!(
      caregiver: caregiver,
      pairing_token: nil # Clear token after pairing
    )
  end
  
  # Check if link is active (has both senior and caregiver)
  def active?
    senior.present? && caregiver.present?
  end
  
  # Check if link is pending (waiting for caregiver)
  def pending?
    senior.present? && caregiver.nil? && pairing_token.present?
  end
end
