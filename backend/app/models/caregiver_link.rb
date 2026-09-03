class CaregiverLink < ApplicationRecord
  belongs_to :senior, class_name: "User"
  belongs_to :caregiver, class_name: "User", optional: true

  enum :permission, { view: 0, manage: 1 }, prefix: true

  validates :pairing_token, uniqueness: true, allow_nil: true
  validate :caregiver_cannot_be_senior

  # How long a pairing token can be redeemed for.
  #
  # Both screens that hand one out have always told the care receiver it lasts a
  # week, and nothing enforced it: redemption asked only whether the token
  # existed and was unclaimed, so one generated months earlier still paired, and
  # the refusal message said "invalid or expired" about a state the code could
  # not produce.
  #
  # What the token carries is why the promise had to become true rather than the
  # promise being dropped. pair_with grants `manage`: whoever redeems it can read
  # this person's reminders, write their telephone number, and ask them to
  # consent to automated calls. Guessing 32 bytes of SecureRandom is not the
  # threat — a credential outliving the sentence that described it is. A care
  # receiver who reads a token to somebody who never uses it has been told it
  # lapses, cannot see it again (#113), and has no screen listing what is still
  # outstanding.
  PAIRING_TOKEN_TTL = 7.days

  # Generate a unique pairing token for linking
  def self.generate_pairing_token(senior:)
    # Generate token with collision detection and safety limit
    max_attempts = 10
    attempts = 0
    token = nil

    loop do
      token = SecureRandom.urlsafe_base64(32)
      break unless exists?(pairing_token: token)

      attempts += 1
      if attempts >= max_attempts
        # Extremely unlikely - use larger token and verify uniqueness
        token = SecureRandom.urlsafe_base64(48)
        raise "Unable to generate unique pairing token" if exists?(pairing_token: token)
        break
      end
    end

    create!(
      senior: senior,
      pairing_token: token,
      permission: :view
    )
  end

  # Complete pairing with a caregiver.
  #
  # Grants manage, which nothing else in the application ever did — the column
  # defaults to view and no screen could change it, so every caregiver who
  # paired normally was permanently unable to reach the phone panel: no number,
  # no verification call, no call language. That is the headline feature, and it
  # was unreachable by anyone who joined the documented way.
  #
  # Invitations grant manage too, so the two paths agree: the product's position
  # is that a caregiver is a caregiver, and somebody trusted enough to be linked
  # is trusted to set the reminders up. Worth knowing what that widens, since
  # this path and that one are not equally consented — a care receiver hands
  # over a pairing token themselves, while an invitation is sent by another
  # caregiver and never asks them anything.
  #
  # It grants the ability to *ask*, not to enable. callable_by_phone? still
  # needs a number, a recorded consent and no opt-out, and only a keypress on a
  # call the care receiver answers can write that consent.
  # Returns true if this caregiver took the link, false if there was nothing
  # left to take.
  #
  # The WHERE clause decides, not a check above it. Redemption used to read the
  # row, judge it, and then write — and two requests holding the same token
  # could both pass the judgement, the later one silently taking the link from
  # the earlier. That is a second caregiver inheriting `manage` over somebody's
  # care record while the first is told they succeeded, and nothing anywhere
  # recording that it happened. The same handshake the acknowledgement and
  # consent paths use: whoever loses sees zero rows updated.
  #
  # `caregiver_cannot_be_senior` is a validation and update_all runs none, so
  # the one rule it enforced is checked here in Ruby. Without it a care receiver
  # could redeem their own token and end up linked to themselves — which used to
  # raise from update! and produce a 500, and now simply fails to claim.
  def pair_with(caregiver:)
    return false if caregiver.nil? || caregiver.id == senior_id

    claimed = self.class
                  .where(id: id, caregiver_id: nil)
                  .where.not(pairing_token: nil)
                  .update_all(
                    caregiver_id: caregiver.id,
                    permission: self.class.permissions[:manage],
                    pairing_token: nil, # Clear token after pairing
                    updated_at: Time.current
                  )

    return false if claimed.zero?

    reload
    true
  end

  # Check if link is active (has both senior and caregiver)
  def active?
    senior.present? && caregiver.present?
  end

  # Check if link is pending (waiting for caregiver)
  def pending?
    senior.present? && caregiver.nil? && pairing_token.present?
  end

  # When this token stops being redeemable. The one place that answer is
  # computed — both screens that print it used to work it out for themselves,
  # which is how the printed date and the check behind it were free to disagree.
  def expires_at
    created_at + PAIRING_TOKEN_TTL
  end

  def expired?
    expires_at.past?
  end

  # Unclaimed *and* still inside its week. Redemption asks this; `pending?` keeps
  # its old meaning, which several callers use to mean "nobody has taken this
  # yet" — a question an expired row still answers yes to, and should, because
  # the row is still there.
  #
  # Expired rows are refused rather than deleted. A link somebody tried to redeem
  # a month late is the one record that shows the attempt was made, and throwing
  # it away is exactly the wrong instinct for a credential over somebody's care.
  def redeemable?
    pending? && !expired?
  end

  private

  def caregiver_cannot_be_senior
    if caregiver_id.present? && caregiver_id == senior_id
      errors.add(:caregiver, "cannot be the same as senior")
    end
  end
end
