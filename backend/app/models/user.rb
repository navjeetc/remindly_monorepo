class User < ApplicationRecord
  enum :role, { senior: 0, caregiver: 1 }, prefix: true
  
  has_many :reminders, dependent: :destroy
  
  # Caregiver relationships
  has_many :senior_links, class_name: "CaregiverLink", foreign_key: "senior_id", dependent: :destroy
  has_many :caregivers, through: :senior_links, source: :caregiver
  
  has_many :caregiver_links, class_name: "CaregiverLink", foreign_key: "caregiver_id", dependent: :destroy
  has_many :seniors, through: :caregiver_links, source: :senior
  
  validates :email, presence: true, uniqueness: true
  attribute :tz, :string, default: "America/New_York"
  
  # Generate a pairing token for this senior
  def generate_pairing_token
    CaregiverLink.generate_pairing_token(senior: self)
  end
end
