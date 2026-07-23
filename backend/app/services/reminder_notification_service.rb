# Notifies caregivers when a senior completes or misses a reminder.
#
# Which reminders reach a given caregiver is that caregiver's choice: each has a
# per-category preference (notify_medication / notify_hydration / notify_routine),
# and only caregivers who opted in to the reminder's category are notified.
# Medication defaults on; hydration and routine default off, since they fire many
# times a day and a caregiver has to ask for that firehose.
#
# Every notification is delivered two ways: an in-app Notification record (what
# the dashboard reads) and an email (so the caregiver is *told*, not merely able
# to find out). Email goes out with deliver_later so a senior's acknowledgement
# request never waits on mail delivery.
#
# This runs inside ReminderNotificationJob, which retries on failure. To make a
# retry safe, per-caregiver delivery is idempotent: if this caregiver has already
# been notified about this occurrence, we skip them, so a retry after a partial
# failure doesn't double-notify the caregivers who already got through.
class ReminderNotificationService
  # A senior tapped "taken" on a reminder.
  def self.notify_acknowledged(occurrence)
    notify(occurrence, kind: :acknowledged)
  end

  # The missed sweep transitioned an occurrence to missed.
  def self.notify_missed(occurrence)
    notify(occurrence, kind: :missed)
  end

  # The caregivers who should hear about this reminder — the senior's caregivers
  # who chose this reminder's category. Public so the missed sweep can skip
  # enqueuing work nobody opted in to. Returns [] for an owner-less reminder.
  #
  # Filtered in Ruby rather than SQL: the chosen categories live in a JSON column
  # (SQLite has no JSON operators here), and a senior has only a handful of
  # caregivers. The reminder's owner is the senior by definition — we don't gate on
  # role, since a senior whose role flag was never set still owns real reminders and
  # caregiver links; the caregiver set is the gate.
  def self.recipients(reminder)
    senior = reminder.user
    return [] unless senior

    category = reminder.category
    senior.caregivers.select { |caregiver| caregiver.notified_for?(category) }
  end

  # kind is :acknowledged or :missed.
  def self.notify(occurrence, kind:)
    reminder = occurrence.reminder
    senior = reminder.user

    recipients(reminder).each do |caregiver|
      next if already_notified?(caregiver, occurrence, kind)

      create_notification(caregiver, senior, reminder, occurrence, kind)
      deliver_email(caregiver, senior, reminder, occurrence, kind)
    end
  end

  # Has this caregiver already been notified about this occurrence? SQLite has no
  # JSON operators, so — as elsewhere in the app — filter this caregiver's recent
  # same-type notifications in Ruby by the occurrence_id we stashed in metadata.
  def self.already_notified?(caregiver, occurrence, kind)
    Notification
      .where(user: caregiver, notification_type: notification_type(kind))
      .where(created_at: 2.days.ago..)
      .any? { |n| n.metadata["occurrence_id"] == occurrence.id }
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

  private_class_method :notify, :already_notified?, :create_notification, :deliver_email,
                       :notification_type, :title, :message
end
