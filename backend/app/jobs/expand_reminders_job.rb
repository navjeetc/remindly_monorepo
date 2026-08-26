# Materialises the occurrences a reminder is due to produce, on a timer rather
# than when somebody happens to open a page.
#
# Until this existed, Recurrence.expand was called from five places and every one
# of them was a controller: creating a reminder, editing one, and
# DashboardController#index — which iterates current_user.reminders, so it only
# fired when the *senior themselves* signed in and loaded their own dashboard. A
# caregiver viewing their senior's page did not expand. The voice page did not
# expand. Nothing on a schedule did.
#
# That was coherent while Remindly was something you looked at: the visit that
# created an occurrence was the same visit that displayed it, so a row was only
# ever needed by somebody who was already making it. Reminder calls invert that.
# Delivery now happens with nobody looking — which is the entire point, since the
# senior it is for may not use a screen at all, and the access design allows one
# who has no email and can never sign in. For that person the chain of page
# visits was never going to run, and their reminders would quietly stop
# materialising a day after setup.
#
# Found on 2026-08-25, the first day calls were live: a senior with four
# reminders had one pending occurrence, and none for the following morning.
class ExpandRemindersJob < ApplicationJob
  queue_as :default

  def perform
    Reminder.includes(:user).find_each do |reminder|
      Recurrence.expand(reminder)
    rescue StandardError => e
      # One reminder with an unparseable rule must not stop the rest of the
      # night's being created. Recurrence.expand parses the RRULE, and a corrupt
      # one raises — which, without this, would take every reminder after it in
      # the batch down too, silently and until somebody read the logs.
      Rails.logger.error "ExpandRemindersJob: reminder #{reminder.id} could not be expanded (#{e.class}: #{e.message})"
    end
  end
end
