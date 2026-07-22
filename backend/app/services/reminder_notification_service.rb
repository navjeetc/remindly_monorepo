# Notifies caregivers when a senior completes or misses a reminder.
#
# Scope is deliberately narrow: only the medication category, and only caregivers
# who have left notify_on_reminder_activity on. Hydration and routine reminders
# fire many times a day and would drown the signal that actually matters — "did
# Mom take her medication?" — so they stay silent here.
#
# Every notification is delivered two ways: an in-app Notification record (what
# the dashboard reads) and an email (so the caregiver is *told*, not merely able
# to find out). Email goes out with deliver_later so a senior's acknowledgement
# request never waits on mail delivery.
class ReminderNotificationService
  # A senior tapped "taken" on a medication reminder.
  def self.notify_acknowledged(occurrence)
    notify(occurrence, kind: :acknowledged)
  end

  # The missed sweep transitioned a medication occurrence to missed.
  def self.notify_missed(occurrence)
    notify(occurrence, kind: :missed)
  end

  # kind is :acknowledged or :missed.
  def self.notify(occurrence, kind:)
    reminder = occurrence.reminder
    return unless reminder.category_medication?

    # The reminder's owner is the senior by definition — that's who the reminder is
    # for. We don't gate on role here: a senior whose role flag was never set still
    # owns real reminders and real caregiver links, and the caregivers scope below
    # is the actual gate (no links, no notifications).
    senior = reminder.user
    return unless senior

    # find_each is a no-op on an empty relation, so no separate emptiness check.
    senior.caregivers.where(notify_on_reminder_activity: true).find_each do |caregiver|
      create_notification(caregiver, senior, reminder, occurrence, kind)
      deliver_email(caregiver, senior, reminder, occurrence, kind)
    end
  end

  def self.create_notification(caregiver, senior, reminder, occurrence, kind)
    Notification.create!(
      user: caregiver,
      notification_type: notification_type(kind),
      title: title(senior, reminder, kind),
      message: message(reminder, occurrence, kind),
      metadata: {
        senior_id: senior.id,
        senior_name: senior.display_name,
        reminder_id: reminder.id,
        reminder_title: reminder.title,
        occurrence_id: occurrence.id,
        scheduled_at: occurrence.scheduled_at&.iso8601 # UTC, for machine use
      }
    )
  end

  def self.deliver_email(caregiver, senior, reminder, occurrence, kind)
    ReminderActivityMailer
      .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence)
      .public_send(kind == :acknowledged ? :completed : :missed)
      .deliver_later
  end

  def self.notification_type(kind)
    kind == :acknowledged ? Notification::TYPES[:reminder_acknowledged] : Notification::TYPES[:reminder_missed]
  end

  def self.title(senior, reminder, kind)
    if kind == :acknowledged
      "#{senior.display_name} completed: #{reminder.title}"
    else
      "#{senior.display_name} missed: #{reminder.title}"
    end
  end

  def self.message(reminder, occurrence, kind)
    # Occurrences are stored in UTC but the reminder carries the senior's zone.
    # Formatting the raw timestamp would report a 9:00 AM dose as 1:00 PM for an
    # Eastern user, since the app leaves Time.zone at UTC.
    when_due = occurrence.scheduled_at&.in_time_zone(reminder.tz)&.strftime("%A, %B %d at %I:%M %p")
    if kind == :acknowledged
      "#{reminder.title} was marked taken#{when_due ? " (due #{when_due})" : ''}."
    else
      "#{reminder.title} was not acknowledged#{when_due ? " (due #{when_due})" : ''}."
    end
  end

  private_class_method :notify, :create_notification, :deliver_email,
                       :notification_type, :title, :message
end
