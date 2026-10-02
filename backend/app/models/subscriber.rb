# Someone who asked to hear from us — the mailing list.
#
# Deliberately not a User. Most people who give an address here are still
# deciding whether Remindly is for them, and creating an account for them would
# mean a dormant User row and a magic-link identity for someone who never asked
# for one.
class Subscriber < ApplicationRecord
  # Deliberately permissive about *shape*. The strict-looking regexes people
  # reach for here reject valid addresses (plus signs, new TLDs, apostrophes)
  # and the only thing that actually proves an address works is sending to it.
  #
  # Length is a different question, and not a cosmetic one: both of these
  # columns are written straight from an unauthenticated public form, and the
  # format regex above is happy with a hundred-thousand-character address.
  # Without a ceiling, the cheapest possible request bloats the table. 254 is
  # the longest address SMTP will carry, so nothing deliverable is refused.
  validates :email,
    presence: true,
    length: { maximum: 254 },
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: "doesn't look like an email address" },
    uniqueness: { case_sensitive: false }

  # Set by our own forms, never typed — but it arrives as a request parameter,
  # so it is only as trustworthy as anything else a stranger can send.
  validates :source, length: { maximum: 60 }, allow_nil: true

  # "  Ann@Example.COM " and "ann@example.com" are one person. Normalising on
  # the way in is what makes the unique index mean anything.
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  # Double opt-in: a signup is a request to join, and the address is on the
  # list only once its owner has clicked the link emailed to it. Everything
  # that treats someone as subscribed -- the welcome email, the notification to
  # us, the CRM, the monthly note -- reads confirmed, never the bare row.
  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :unconfirmed, -> { where(confirmed_at: nil) }

  # How long a confirmation link works, and how long an unconfirmed signup is
  # kept after its latest link was sent before PruneUnconfirmedSubscribersJob
  # deletes it.
  CONFIRMATION_WINDOW = 7.days

  # At most one confirmation email per address per hour. The form can be
  # submitted again and again with somebody else's address; without this, the
  # double opt-in meant to stop inbox flooding would itself flood the inbox.
  CONFIRMATION_RESEND_AFTER = 1.hour

  # Campaigns go out from GoHighLevel, so the list there follows this table:
  # confirming tags the contact, unsubscribing (which deletes the row) untags it.
  # Does nothing until GHL credentials exist. See GoHighLevel.
  #
  # Leaving records a pending CRM removal, so the promise to delete the address
  # holds even while the sync has no credentials; the job clears it once the
  # CRM no longer has them. Confirming forgets it -- not merely signing up
  # again: an unconfirmed signup is not on the list, and if it erased the
  # removal of someone who had just left, nothing would delete them from the
  # CRM. An unconfirmed signup never reached the CRM, so leaving records
  # nothing for it.
  #
  # Inside the subscriber's own transaction, not after it commits: the row and
  # its pending removal must change together. As after_commit callbacks, a
  # quick unsubscribe-then-resubscribe could run them out of order, so a late
  # clear erased a newer removal, or a late record kept an address that should
  # have gone. Here the database's commit order decides, and a rolled-back
  # unsubscribe leaves no removal behind.
  after_save -> { CrmRemoval.clear(email) }, if: :just_confirmed?
  after_destroy -> { CrmRemoval.record(email) }, if: :confirmed?

  # Only the job waits for the commit, so it never runs against a change that
  # did not happen. It reads whether the address is on the list when it runs,
  # so it only needs to know which address changed: when it is confirmed, and
  # when a confirmed subscriber leaves.
  after_commit -> { SyncSubscriberToCrmJob.perform_later(email) }, on: %i[create update], if: :just_confirmed?
  after_commit -> { SyncSubscriberToCrmJob.perform_later(email) }, on: :destroy, if: :confirmed?

  def confirmed? = confirmed_at.present?

  def just_confirmed? = saved_change_to_confirmed_at? && confirmed?

  # Joins the list. Returns true only for the request that actually made the
  # change, so the welcome email and the notification to us go out once
  # however often, or however simultaneously, the button is pressed.
  #
  # with_lock, not a plain check-then-write: two requests (a double-click is
  # enough) each loaded the row unconfirmed, both passed the check, and both
  # sent the emails. with_lock rereads the row inside a transaction SQLite
  # opens IMMEDIATE, so the second waits for the first and then sees it
  # confirmed. update! rather than update_all so the CRM callbacks still run.
  def confirm!
    with_lock do
      next false if confirmed?

      update!(confirmed_at: Time.current)
      true
    end
  end

  # Expires a fixed time after the confirmation email was requested, the same
  # moment PruneUnconfirmedSubscribersJob counts from, rather than a window
  # from whenever this runs. It runs when the mail job renders the email, which
  # a backed-up queue can delay; counted from then, the link outlived the row
  # it names and failed before its promised seven days were up.
  def confirmation_token
    signed_id(purpose: :confirm_subscription, expires_at: (confirmation_sent_at || created_at) + CONFIRMATION_WINDOW)
  end

  def self.find_by_confirmation_token(token)
    find_signed(token, purpose: :confirm_subscription)
  end

  # Emails the confirmation link, unless the address is already on the list or
  # one was sent within the last hour. Returns whether it sent. Locked for the
  # same reason as confirm!: simultaneous signups for one address each passed
  # the hourly check before any had saved, and each sent an email -- the very
  # flood the limit exists to stop.
  def request_confirmation
    sent = with_lock do
      next false if confirmed?
      next false if confirmation_sent_at && confirmation_sent_at > CONFIRMATION_RESEND_AFTER.ago

      update!(confirmation_sent_at: Time.current)
      true
    end

    SubscriberMailer.confirmation(self).deliver_later if sent
    sent
  end

  # The same fact User tracks, for the same reason: an address a mail provider
  # has permanently refused stays refused, and subscribers:send_monthly_note
  # must stop re-enqueuing it every month rather than rediscovering the same
  # bounce forever. See db/migrate/*_add_email_undeliverable_at_to_subscribers.
  scope :deliverable, -> { where(email_undeliverable_at: nil) }

  def email_deliverable? = email_undeliverable_at.nil?

  # Idempotent for the same reason as User#mark_email_undeliverable!: a
  # conditional UPDATE rather than check-then-write, so two jobs discarding the
  # same address at once cannot have the second quietly move the first's
  # timestamp forward. Kept in step with that method rather than shared with it
  # -- the two models have no common ancestor, and duplicating fifteen lines
  # cost less than a concern would, here, for two callers.
  def mark_email_undeliverable!(at: Time.current)
    claimed = self.class.where(id: id, email_undeliverable_at: nil)
      .update_all(email_undeliverable_at: at)

    recorded = claimed.positive? ? at : self.class.where(id: id).pick(:email_undeliverable_at)

    write_attribute(:email_undeliverable_at, recorded)
    clear_attribute_changes([ :email_undeliverable_at ])

    self
  end

  # Signing up twice is a normal thing to do — people forget. It should be
  # indistinguishable from signing up once, rather than an error page telling a
  # stranger that their address is already on a list.
  #
  # @param email [String]
  # @param source [String, nil] the page the address came from
  # @return [Subscriber] persisted, or a new record carrying validation errors
  def self.subscribe(email:, source: nil)
    # Look for the existing record before validating, not after. Validating
    # first means the uniqueness rule fires on the second signup and the caller
    # gets an error record — which is exactly the "your address is already on a
    # list" response this method exists to avoid. normalizes has already run by
    # this point, so the lookup matches however the address was typed.
    record = new(email: email, source: source)
    existing = find_by(email: record.email) if record.email.present?
    return existing if existing

    record.tap(&:save)
  rescue ActiveRecord::RecordNotUnique
    # Lost a race. Two requests for the same address — a double-clicked button
    # is enough — can both get past the lookup and the uniqueness validation
    # before either has committed, and then the database index rejects the
    # second insert. Without this the loser gets a 500 on what is, from the
    # person's point of view, a perfectly ordinary signup.
    find_by(email: record.email) || record
  end
end
