class Acknowledgement < ApplicationRecord
  belongs_to :occurrence
  enum :kind, { taken: 0, snooze: 1, skip: 2 }, prefix: true
end
