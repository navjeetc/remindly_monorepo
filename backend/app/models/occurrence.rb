class Occurrence < ApplicationRecord
  belongs_to :reminder
  enum :status, { pending: 0, acknowledged: 1, missed: 2 }, prefix: true
end
