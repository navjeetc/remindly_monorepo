class User < ApplicationRecord
  enum :role, { senior: 0, caregiver: 1 }, prefix: true
  has_many :reminders, dependent: :destroy
  validates :email, presence: true, uniqueness: true
  attribute :tz, :string, default: "America/New_York"
end
