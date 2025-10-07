class Occurrence < ApplicationRecord
  belongs_to :reminder
  has_many :acknowledgements, dependent: :destroy
  enum :status, { pending: 0, acknowledged: 1, missed: 2 }, prefix: true
end
