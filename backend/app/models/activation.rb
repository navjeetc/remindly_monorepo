# How far the accounts created in a period got, for Admin → Traffic.
#
# Page views answer "did anyone come"; this answers "did anyone start using it",
# which is what an ad is actually paying for. Each step counts the accounts from
# the cohort that reached it. They are not quite a strict chain: somebody can be
# connected to a person who agreed long ago and has no reminder yet.
#
#   created     somebody asked for a sign-in link with this address
#   signed_in   they opened it (users.first_signed_in_at)
#   added       they set up, or were connected to, somebody to remind
#   reminded    that person has at least one reminder
#   agreed      that person said yes — the link is active
#
# The cohort is accounts with an email, which is every self-serve sign-up and
# excludes the care receivers a caregiver creates (they have none). Admins are
# left out. Grouped by users.signup_source, the ?from= tag the account was
# created from, which is the same tag PageCount tallies for page views.
#
# A plain object rather than a table: it is a handful of counts over rows that
# already exist, and nothing about it needs remembering.
class Activation
  STEPS = {
    created: "Accounts created",
    signed_in: "Signed in",
    added: "Added someone",
    reminded: "Wrote a reminder",
    agreed: "They agreed"
  }.freeze

  # The label for accounts that arrived without a tag.
  UNTAGGED = "(no tag)".freeze

  def initialize(since:)
    @since = since
  end

  # { created: 12, signed_in: 9, ... } for the whole cohort.
  def totals
    STEPS.keys.index_with { |step| scope_for(step).count }
  end

  # [["meta", { created: 5, ... }], [UNTAGGED, { ... }]], most accounts first.
  def by_source
    counts = STEPS.keys.index_with { |step| scope_for(step).group(:signup_source).count }

    counts[:created].keys
      .map { |source| [ source || UNTAGGED, STEPS.keys.index_with { |step| counts[step].fetch(source, 0) } ] }
      .sort_by { |_, steps| -steps[:created] }
  end

  private

  def cohort
    User.where(created_at: @since.beginning_of_day..)
      .where.not(email: nil)
      .where("role IS NULL OR role != ?", User.roles.fetch("admin"))
  end

  def scope_for(step)
    case step
    when :created then cohort
    when :signed_in then cohort.where.not(first_signed_in_at: nil)
    when :added then cohort.where(id: CaregiverLink.select(:caregiver_id))
    when :reminded then cohort.where(id: CaregiverLink.where(senior_id: Reminder.select(:user_id)).select(:caregiver_id))
    when :agreed then cohort.where(id: CaregiverLink.state_active.select(:caregiver_id))
    end
  end
end
