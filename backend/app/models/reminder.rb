class Reminder < ApplicationRecord
  belongs_to :user
  has_many :occurrences, dependent: :destroy
  enum :category, { medication: 0, hydration: 1, routine: 2 }, prefix: true
  validates :title, :rrule, :tz, presence: true
end
