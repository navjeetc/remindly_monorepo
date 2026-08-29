class User < ApplicationRecord
  enum :role, { senior: 0, caregiver: 1, admin: 2 }, prefix: true

  # How large this person needs the interface. Stored per user rather than in
  # the browser because the people who need it most are the least likely to set
  # it twice — a senior who fixes the text on the tablet should not find it
  # small again on the phone their daughter hands them.
  #
  # validate: true because without it an unknown value raises ArgumentError on
  # assignment, which a form post turns into a 500 rather than the "please pick
  # one" the rest of this form gives you.
  enum :text_size, { normal: 0, large: 1, larger: 2, largest: 3 }, prefix: true, validate: true

  # Percentages for the root font size. Tailwind sizes text *and* spacing in
  # rem, so moving the root moves padding and tap targets with the type, which
  # is the point: bigger words in the same cramped buttons would help nobody.
  # Breakpoints are px and stay put, so the responsive layout is unaffected.
  #
  # The single list of sizes: the layout reads the percentage, the form draws
  # its choices from the keys, and neither can drift from the other.
  TEXT_SCALES = { "normal" => 100, "large" => 115, "larger" => 130, "largest" => 150 }.freeze

  # What the profile form offers: the stored value, its label, and the pixel
  # size to draw the label at. The preview is derived from the scale rather
  # than listed separately, so a size cannot ship previewing as something it
  # is not.
  BASE_TEXT_PX = 16

  def self.text_size_choices
    TEXT_SCALES.map { |size, scale| [ size, size.titleize, (BASE_TEXT_PX * scale / 100.0).round ] }
  end

  def text_scale = TEXT_SCALES.fetch(text_size, 100)

  # The language Remindly speaks to this person in on the telephone. It is the
  # senior's setting, because the senior is the one who hears it — a caregiver
  # sets it on their behalf from the senior's page, since many of them never
  # sign in.
  #
  # Two identifiers here, and they are not the same thing. The key is Telnyx's
  # language code, which selects the accent the voice reads with; :locale is
  # the Rails locale holding the words. They differ because es-ES, es-MX and
  # es-US are three accents reading one Spanish translation, and collapsing
  # them would mean a translation file per accent.
  #
  # Only codes in Telnyx's speak enum belong here. Cantonese (yue-HK) is not in
  # it at any price, which is why this list starts where it does.
  SPOKEN_LANGUAGES = {
    "en-US" => { label: "English", locale: :en },
    "es-US" => { label: "Español (Spanish)", locale: :es }
  }.freeze

  validates :spoken_language, inclusion: { in: SPOKEN_LANGUAGES.keys }

  # What the form may offer today. English is always available; the rest wait on
  # a native speaker having read the script, which is what the flag records.
  # Note this gates the *choice*, not playback: a senior already set to Spanish
  # keeps hearing Spanish if the flag is turned back off, because taking away a
  # language somebody is relying on is worse than the risk it was hiding.
  def self.selectable_spoken_languages
    return SPOKEN_LANGUAGES if FeatureFlag.enabled?(:translated_calls)

    SPOKEN_LANGUAGES.slice("en-US")
  end

  # The locale the call script is read from. Falls back rather than raising:
  # a row holding something unknown should still get a call it can act on.
  def spoken_locale
    SPOKEN_LANGUAGES.dig(spoken_language, :locale) || :en
  end

  def spoken_language_label
    SPOKEN_LANGUAGES.dig(spoken_language, :label) || spoken_language
  end

  # What each role is called on screen. The stored value stays `senior` — it is
  # in the enum, in four foreign keys and in every spec — while the interface
  # says "care receiver", which a caregiver reviewing Remindly asked for: not
  # everyone being cared for is old, and the word narrows the product to a
  # subset of the people it serves.
  #
  # A label rather than a rename on purpose. Renaming the enum means migrating
  # data to change a word nobody stores for its own sake.
  ROLE_LABELS = { "senior" => "Care receiver", "caregiver" => "Caregiver", "admin" => "Admin" }.freeze

  def role_label
    ROLE_LABELS.fetch(role.to_s, role.to_s.titleize)
  end

  # Whether this user may change things for another — set up reminders, tasks
  # and unavailability, rather than only watch them.
  #
  # Everybody manages themselves: a care receiver is not a caregiver on their own
  # link and has no permission recorded anywhere, because the data is theirs.
  #
  # Every caregiver holds manage today, so this is a guard for a role that does
  # not exist yet rather than one anybody currently trips. It is written now
  # because the alternative is a permission whose name promises a restriction
  # the code does not apply — which reads like a safety mechanism and is not one.
  def manages?(other)
    return true if self == other

    caregiver_links.where(senior_id: other.id, permission: :manage).exists?
  end

  # Roles a user may choose for themselves — at onboarding, or later from their
  # profile. Admin is deliberately excluded: it is never self-granted, and this
  # path also refuses to touch an existing admin's role.
  SELF_ASSIGNABLE_ROLES = %w[senior caregiver].freeze

  has_many :reminders, dependent: :destroy

  # Caregiver relationships
  has_many :senior_links, class_name: "CaregiverLink", foreign_key: "senior_id", dependent: :destroy
  has_many :caregivers, through: :senior_links, source: :caregiver

  has_many :caregiver_links, class_name: "CaregiverLink", foreign_key: "caregiver_id", dependent: :destroy
  has_many :seniors, through: :caregiver_links, source: :senior

  # Task relationships
  has_many :tasks_as_senior, class_name: "Task", foreign_key: "senior_id", dependent: :destroy
  has_many :assigned_tasks, class_name: "Task", foreign_key: "assigned_to_id", dependent: :nullify
  has_many :created_tasks, class_name: "Task", foreign_key: "created_by_id", dependent: :nullify
  has_many :task_comments, dependent: :destroy
  has_many :caregiver_availabilities, foreign_key: "caregiver_id", dependent: :destroy

  # Scheduling integrations
  has_many :scheduling_integrations, dependent: :destroy

  # Notifications
  has_many :notifications, dependent: :destroy

  # Time blocks
  has_many :time_blocks, dependent: :destroy

  # Ahoy analytics
  has_many :visits, class_name: "Ahoy::Visit", dependent: :destroy
  has_many :events, class_name: "Ahoy::Event", dependent: :destroy

  # Label from Rails, value from IANA — see #tz= for why the value must be the
  # identifier. Deduped because several Rails zone names share one IANA zone
  # ("Edinburgh" and "London" are both Europe/London), and a select holding the
  # same value twice cannot round-trip the second one.
  TIMEZONE_OPTIONS = ActiveSupport::TimeZone.all
    .map { |zone| [ zone.to_s, zone.tzinfo.name ] }
    .uniq { |_label, identifier| identifier }
    .freeze

  validates :email, presence: true, uniqueness: true
  validates :name, presence: true, on: :update, if: -> { !new_record? }
  attribute :tz, :string, default: "America/New_York"
  validates :tz, presence: true
  validate :tz_resolves_to_a_real_zone
  validate :phone_is_e164, if: -> { phone.present? }

  # Consent is to a number, not to a person.
  #
  # Change the number and every fact about the old one stops applying: the new
  # number has not been verified and its owner has not agreed to anything. A
  # caregiver editing this field would otherwise inherit consent given by
  # somebody else — which is the failure the whole consent design exists to
  # prevent, reached through a text field rather than a form full of promises.
  #
  # An opt-out is deliberately *not* cleared. Someone who said stop said it about
  # being telephoned, not about a particular number, and a caregiver must not be
  # able to undo that by editing a field. Lifting it takes a fresh keypress.
  before_save :forget_consent_when_the_number_changes

  # Addresses a mail provider has permanently refused — a hard bounce, meaning
  # the mailbox does not exist. Postmark marks such an address inactive and
  # rejects every later send, so continuing to try achieves nothing and actively
  # costs something: mailbox providers judge a sender on how much mail it aims
  # at addresses that are not there, and every message here now leaves the one
  # address that magic-link logins also use.
  #
  # Notification mail should be sent to `deliverable` users only. Magic links
  # are deliberately not filtered — someone signing in is asking for that one
  # message, and refusing to try would turn a bounced address into a silent
  # lockout with nothing in the logs.
  scope :deliverable, -> { where(email_undeliverable_at: nil) }

  def email_deliverable? = email_undeliverable_at.nil?

  # Idempotent: the first refusal is the one worth dating, and a later one
  # should not keep moving the timestamp forward.
  #
  # Done as a conditional UPDATE rather than check-then-write. Two mail jobs for
  # the same address running at once — one coverage gap, one missed dose, which
  # is an ordinary morning — can both read nil before either writes, and the
  # later write would then quietly replace the earlier date. The WHERE clause
  # makes the database pick a winner instead.
  def mark_email_undeliverable!(at: Time.current)
    claimed = self.class.where(id: id, email_undeliverable_at: nil)
      .update_all(email_undeliverable_at: at)

    # Keep this instance honest either way: adopt our own timestamp if we won,
    # and the winner's if we did not, rather than going on believing the address
    # is still good.
    recorded = claimed.positive? ? at : self.class.where(id: id).pick(:email_undeliverable_at)

    write_attribute(:email_undeliverable_at, recorded)
    clear_attribute_changes([ :email_undeliverable_at ])

    self
  end

  # Class methods to get users by role
  def self.caregivers
    where(role: :caregiver)
  end

  def self.seniors
    where(role: :senior)
  end

  # Generate a pairing token for this senior
  def generate_pairing_token
    CaregiverLink.generate_pairing_token(senior: self)
  end

  # Zones are stored as IANA identifiers ("America/New_York"), never as Rails
  # zone names ("Eastern Time (US & Canada)"). Both spellings resolve through
  # ActiveSupport::TimeZone[], which is exactly why a column holding a mix of
  # the two sat there for months without anything failing.
  #
  # What it did break was the round trip through the profile form. That select's
  # <option> values were Rails names, so a user whose column held the IANA
  # default matched no option at all; the browser then showed the first option
  # in the list, and saving the form wrote it back. The first entry of
  # ActiveSupport::TimeZone.all is International Date Line West, so opening the
  # profile and pressing Save silently moved a user to UTC-12 — seventeen hours
  # off Eastern, which for this app means every reminder fires on the wrong day.
  # It happened to the first real signup, on her first day.
  #
  # The select now offers identifiers, and this normalizes whatever arrives, so
  # both ends of that round trip speak one language. An unresolvable value is
  # kept as-is rather than quietly dropped, so the validation below can name it.
  def tz=(value)
    super(ActiveSupport::TimeZone[value.to_s]&.tzinfo&.name || value)
  end

  # A zone outside Rails' curated list is a legitimate thing to be stored (it
  # resolves fine) but would match no option and put this form right back where
  # it started, so it is added to the list rather than dropped from it.
  def timezone_options
    return TIMEZONE_OPTIONS if TIMEZONE_OPTIONS.any? { |_label, identifier| identifier == tz }

    TIMEZONE_OPTIONS + [ [ tz, tz ] ]
  end

  # Display name - uses nickname if available, otherwise name, otherwise email
  def display_name
    nickname.presence || name.presence || email
  end

  # Friendly name for seniors to recognize caregivers
  def friendly_name
    nickname.presence || name.presence || email.split("@").first
  end

  # Reminder categories this caregiver wants completion/miss notifications for.
  # Normalized on write: only real, deduped categories are stored, so a stray
  # value from the form is dropped. A category later removed from the enum is
  # cleaned from a user's stored set the next time they save preferences, not
  # retroactively — though a removed category would no longer match any reminder
  # anyway, so it can't produce a notification in the meantime.
  def notify_reminder_categories=(values)
    super(Array(values).map(&:to_s).select { |c| Reminder.categories.key?(c) }.uniq)
  end

  def notified_for?(category)
    notify_reminder_categories.include?(category.to_s)
  end

  # Let a user set their own role at onboarding — once. Only the non-privileged
  # roles are allowed, an existing admin is never changed through here, and a
  # role already chosen is not changed at all.
  #
  # Named for the restriction rather than the action. The old name,
  # assign_self_role, read as a general setter, and a profile button duly called
  # it to switch somebody back and forth: a caregiver sees the people they care
  # for, a care receiver sees their own reminders, so pressing it swapped the
  # whole screen and the only way back was pressing it again. Nothing recorded
  # that it had happened, so there is no evidence it was ever used, and none
  # that it was not.
  #
  # The refusal lives here rather than only in the view, because a removed
  # button with a live endpoint behind it is not a removal. Somebody who
  # genuinely picked wrong asks an admin, who has a screen for it that emails
  # them about the change — more of a record than this path ever left.
  #
  # The admin guard and the write are one atomic statement — a compare-and-swap
  # that excludes admins in its WHERE — so a concurrent promotion can't slip in
  # between a stale in-memory read and the write and get clobbered. update_all
  # also skips the name-presence-on-update validation a brand-new user can't yet
  # satisfy.
  #
  # The problem underneath is untouched: roles are exclusive, so a daughter
  # managing her mother's reminders cannot also have her own (#122). Switching
  # was never a fix for that, only a way to trade one for the other.
  def choose_role_once(new_role)
    new_role = new_role.to_s
    return false unless SELF_ASSIGNABLE_ROLES.include?(new_role)
    return false if role.present?

    # "role IS NULL OR role <> admin" — brand-new users have a NULL role, and a
    # bare `role <> admin` would exclude them (NULL comparisons are never true).
    changed = self.class.where(id: id)
      .where("role IS NULL OR role <> ?", self.class.roles[:admin])
      .update_all(role: self.class.roles.fetch(new_role))
    return false if changed.zero?

    self.role = new_role # keep this in-memory instance in sync with the DB
    true
  end

  # Outbound reminder calls are restricted to 8am-9pm in the *called party's*
  # own local time. That is a legal limit, not a preference, and it is what makes
  # tz load-bearing for phone reminders rather than a display convenience: the
  # profile bug that silently moved savers to UTC-12 would, under this feature,
  # have telephoned them in the middle of the night.
  #
  # 8...21 covers the hours 8 through 20, so 20:59 is inside the window and 21:00
  # is not.
  CALLING_HOURS = (8...21)

  # Whether Remindly may telephone this person at all.
  #
  # Deliberately not the same question as call_reminders_enabled?. That flag is
  # written by one thing only -- a completed verification call -- but it is still
  # a cached answer, and the facts underneath it can change without it: a number
  # cleared, an opt-out recorded. Reading the facts means a stale flag cannot
  # authorise a call on its own.
  #
  # An opt-out beats everything, including a consent recorded afterwards by some
  # other route, because there is no other route.
  def callable_by_phone?
    return false if call_opted_out_at.present?
    return false if phone.blank?
    return false if call_consent_at.blank?

    call_reminders_enabled?
  end

  # This person's own clock, or nil when tz does not resolve.
  #
  # Callers must handle the nil rather than formatting whatever comes back:
  # in_time_zone raises ArgumentError on an unknown identifier, so the naive
  # version turns a bad tz into a 500 in whichever request touches it first.
  # tz_resolves_to_a_real_zone should keep that from happening, so this is
  # defence in depth rather than a hole being plugged -- but the validation is
  # newer than the column, it cannot speak for a row written by a migration or
  # by hand, and VoiceReminderJob already decided this same field was worth
  # guarding this same way.
  def local_time(at: Time.current)
    zone = ActiveSupport::TimeZone[tz.to_s]
    return nil if zone.nil?

    at.in_time_zone(zone)
  end

  def within_calling_hours?(at: Time.current)
    local = local_time(at: at)

    # A zone we cannot resolve means we do not know what time it is where this
    # person is, and "probably daytime" is not a defence. Blocking is the only
    # safe default -- a call placed at 3am cannot be taken back.
    return false if local.nil?

    CALLING_HOURS.cover?(local.hour)
  end

  private

  def tz_resolves_to_a_real_zone
    return if tz.blank?

    errors.add(:tz, "is not a valid timezone") unless ActiveSupport::TimeZone[tz]
  end

  def forget_consent_when_the_number_changes
    return unless will_save_change_to_phone?

    # Nothing to forget when there was no previous number *and* no consent facts
    # to inherit — a new record, or the first number on a record that has none.
    # Without some form of this the callback wipes consent being granted in the
    # same save, which reads as security and is simply a bug: it defeats any
    # single write that sets both, silently.
    #
    # The consent columns are checked as well as the number, because a record can
    # hold consent with no phone: consent! writes the timestamps through
    # update_all, and a later console repair or data fix could blank the number
    # without touching them. Skipping on a blank previous number alone would then
    # let the *first* number saved afterwards inherit an agreement given for a
    # different handset — arriving at the exact failure this callback exists to
    # prevent, by the one door left open.
    return if phone_in_database.blank? &&
              call_consent_at_in_database.blank? &&
              phone_verified_at_in_database.blank?

    self.phone_verified_at = nil
    self.call_consent_at = nil
    self.call_reminders_enabled = false
  end

  def phone_is_e164
    # E.164: leading +, 1-3 digit country code, then up to 12 digits.
    return if phone.match?(/\A\+[1-9]\d{7,14}\z/)

    errors.add(:phone, "must be a valid E.164 number like +15551234567")
  end
end
