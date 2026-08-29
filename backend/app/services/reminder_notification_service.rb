# Notifies caregivers when a senior completes or misses a reminder.
#
# Which reminders reach a given caregiver is that caregiver's choice: each keeps a
# set of opted-in reminder categories (notify_reminder_categories), and only
# caregivers whose set includes the reminder's category are notified. Medication is
# in the set by default; hydration and routine are not, since they fire many times
# a day and a caregiver has to ask for that firehose.
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

  # A call for a critical reminder went unanswered.
  #
  # Fired on each unanswered attempt rather than only the first, and deduped
  # by the unique index. Doing it once would mean a lost or redelivered
  # webhook resulting in silence for the one reminder that cannot afford it.
  #
  # Every linked caregiver hears, not only those who opted into the reminder's
  # category. The category preference exists so a caregiver is not woken by
  # hydration reminders; a dose somebody marked time-critical is the case it was
  # never meant to filter out.
  #
  # Quiet hours are deliberately ignored — there are none for caregiver email,
  # and a critical dose at 3am is exactly when somebody should be woken.
  def self.notify_unanswered(occurrence, attempts_remaining:)
    reminder = occurrence.reminder
    senior = reminder&.user
    return unless senior && reminder.critical?

    senior.caregivers.each do |caregiver|
      # The unique index decides, as everywhere else here: a redelivered webhook
      # cannot mail the same caregiver twice about the same occurrence.
      next unless create_notification(caregiver, senior, reminder, occurrence, :unanswered)

      # Same rule as the acknowledged and missed paths: an address Postmark has
      # already refused gets the in-app alert and no job. Three attempts per
      # occurrence times every critical dose would otherwise be a lot of
      # discarded jobs for a mailbox that is not coming back.
      next unless caregiver.email_deliverable?

      begin
        ReminderActivityMailer
          .with(caregiver: caregiver, senior: senior, reminder: reminder,
                occurrence: occurrence, attempts_remaining: attempts_remaining)
          .unanswered
          .deliver_later
      rescue StandardError => e
        # The notification row is the dedup marker, and it is already written.
        # If enqueueing fails the second and third attempts would find that row
        # and skip silently, so the caregiver would never be mailed even once
        # the queue recovers. Dropping the marker lets the next attempt — five
        # minutes away — try again.
        Rails.logger.error(
          "Critical alert enqueue failed for caregiver #{caregiver.id}, occurrence #{occurrence.id}: " \
          "#{e.class}: #{e.message}"
        )
        Notification.where(user: caregiver, occurrence_id: occurrence.id,
                           notification_type: Notification::TYPES[:reminder_unanswered]).delete_all
      end
    end
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
      # The insert decides, not the check. Two workers handling redelivered
      # deliveries of the same event could both pass a SELECT and each create an
      # alert and send an email; the unique index on
      # (user_id, notification_type, occurrence_id) now refuses the second, and
      # this returns nil so nothing further is done for that caregiver.
      next unless create_notification(caregiver, senior, reminder, occurrence, kind)

      # Same rule as coverage gaps, and it matters more here: a coverage gap
      # mails once a day, while this fires on every completed and missed
      # reminder — several times a day per senior. An address Postmark has
      # permanently refused would generate that many discarded jobs and that
      # many pointless API calls, which is the noise this is meant to end
      # rather than relocate. The in-app notification above is unconditional:
      # a dead mailbox is no reason to hide a missed dose from a caregiver.
      next unless caregiver.email_deliverable?

      deliver_email(caregiver, senior, reminder, occurrence, kind)
    end
  end

  # Returns the notification, or nil when this caregiver has already been told
  # about this occurrence. occurrence_id is a real column purely so this can be
  # a uniqueness constraint — it used to live only inside the json metadata,
  # where nothing is indexable, which left the check a SELECT that a concurrent
  # worker could race. metadata keeps its copy for the readers that use it.
  def self.create_notification(caregiver, senior, reminder, occurrence, kind)
    Notification.create!(
      user: caregiver,
      notification_type: notification_type(kind),
      occurrence_id: occurrence.id,
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
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def self.deliver_email(caregiver, senior, reminder, occurrence, kind)
    ReminderActivityMailer
      .with(caregiver: caregiver, senior: senior, reminder: reminder, occurrence: occurrence)
      .public_send(kind == :acknowledged ? :completed : :missed)
      .deliver_later
  end

  def self.notification_type(kind)
    case kind
    when :acknowledged then Notification::TYPES[:reminder_acknowledged]
    when :unanswered   then Notification::TYPES[:reminder_unanswered]
    else                    Notification::TYPES[:reminder_missed]
    end
  end

  def self.title(senior, reminder, kind)
    case kind
    when :acknowledged then "#{senior.display_name} completed: #{reminder.title}"
    # Not "missed" — two more calls are still coming, and a dashboard alert
    # saying missed while the phone is about to ring again would be wrong for
    # the ten minutes it matters most.
    when :unanswered   then "#{senior.display_name} hasn't answered: #{reminder.title}"
    else                    "#{senior.display_name} missed: #{reminder.title}"
    end
  end

  def self.message(reminder, occurrence, kind)
    # Occurrences are stored in UTC but the reminder carries the senior's zone.
    # Formatting the raw timestamp would report a 9:00 AM dose as 1:00 PM for an
    # Eastern user, since the app leaves Time.zone at UTC.
    when_due = occurrence.scheduled_at&.in_time_zone(reminder.tz)&.strftime("%A, %B %d at %I:%M %p")
    case kind
    when :acknowledged
      "#{reminder.title} was marked done#{when_due ? " (due #{when_due})" : ''}."
    when :unanswered
      # Not "was not completed": the title says nobody has answered yet, and a
      # body underneath it announcing the dose was not completed would say the
      # opposite of the alert it belongs to, while two calls are still coming.
      "#{reminder.title}: no answer yet#{when_due ? " (due #{when_due})" : ''}. More calls are on the way."
    else
      "#{reminder.title} was not completed#{when_due ? " (due #{when_due})" : ''}."
    end
  end

  private_class_method :notify, :create_notification, :deliver_email,
                       :notification_type, :title, :message
end
