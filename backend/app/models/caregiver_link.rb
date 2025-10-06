class CaregiverLink < ApplicationRecord
  belongs_to :senior, class_name: "User"
  belongs_to :caregiver, class_name: "User"
  enum :permission, { view: 0, manage: 1 }, prefix: true
end
