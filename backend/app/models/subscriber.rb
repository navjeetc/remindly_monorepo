# Someone who asked to hear from us — the mailing list.
#
# Deliberately not a User. Most people who give an address here are still
# deciding whether Remindly is for them, and creating an account for them would
# mean a dormant User row and a magic-link identity for someone who never asked
# for one.
class Subscriber < ApplicationRecord
  # Deliberately permissive. The strict-looking regexes people reach for here
  # reject valid addresses (plus signs, new TLDs, apostrophes) and the only
  # thing that actually proves an address works is sending to it.
  validates :email,
    presence: true,
    format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, message: "doesn't look like an email address" },
    uniqueness: { case_sensitive: false }

  # "  Ann@Example.COM " and "ann@example.com" are one person. Normalising on
  # the way in is what makes the unique index mean anything.
  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

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
