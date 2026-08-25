class Reminder < ApplicationRecord
  belongs_to :user
  has_many :occurrences, dependent: :destroy
  enum :category, { medication: 0, hydration: 1, routine: 2 }, prefix: true
  validates :title, :rrule, :tz, presence: true

  # A reminder is kept in the clock of the person it is for, always.
  #
  # tz used to be whatever the caller supplied — RemindersController permits it
  # in reminder_params — so a caregiver whose own device said New Delhi created
  # New York seniors' reminders stamped "New Delhi". Nothing corrected it
  # afterwards, and Recurrence expands the schedule in this column, so those
  # reminders were pinned to a zone that has never observed daylight saving:
  # every spring and autumn the senior's clock moved and the reminder did not.
  # Two on the production account had drifted an hour by the time anybody
  # noticed, and one had drifted out of the 8am-9pm calling window entirely,
  # which would have silently stopped it ever telephoning.
  #
  # Set here rather than in each controller because there are three ways in —
  # the dashboard, the JSON API and the console — and only one of them was
  # getting it right. A denormalised copy that cannot disagree with its source
  # is worth having; one that can is exactly this bug.
  before_validation :keep_the_clock_of_the_person_it_is_for

  private

  def keep_the_clock_of_the_person_it_is_for
    self.tz = user.tz if user&.tz.present?
  end
end
