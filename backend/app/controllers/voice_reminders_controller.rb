# frozen_string_literal: true

# The page a care receiver's device leaves open all day, and the JSON it polls.
#
# Extracted from DashboardController, which authenticates every action through
# `current_user` and a caregiver-shaped session. This page is the one place a
# second kind of credential is going to be honoured — a reminder link, where the
# secret in a bookmarked URL is the whole credential — and that must not become
# a flag inside a controller whose other twenty actions manage caregivers,
# permissions and telephone numbers.
#
# Its own controller makes the boundary structural: a link-mode cookie is read
# here and nowhere else, so a route added to the dashboard tomorrow cannot
# accidentally accept one. Forgetting to opt a controller in fails closed,
# which is the property `docs/SENIOR_ACCESS_DESIGN.md` asks for and the reason
# this is a separate file rather than two more `before_action` exceptions.
class VoiceRemindersController < WebController
  before_action :authenticate!
  before_action :care_receivers_only!, only: :show

  layout "dashboard"

  def show; end

  # Polled by public/voice_reminders.js. Everything due today and still pending,
  # in the care receiver's own timezone — the announcement decides what to say
  # from this, so it deliberately does not filter on how the row was created.
  def today
    # Answered as JSON whatever the request's format, which is how this endpoint
    # behaved before it moved. Deciding by format instead would make the refusal
    # depend on whether the caller sent an Accept header — so a hand-made
    # request would get a redirect where fetch() gets a 401, and the boundary
    # would read differently depending on who was knocking.
    return render json: { error: "Unauthorized" }, status: :unauthorized unless current_user.role_senior?

    tz = ActiveSupport::TimeZone[current_user.tz]
    day = tz.now.beginning_of_day..tz.now.end_of_day

    occurrences = Occurrence
      .joins(:reminder)
      .where(reminders: { user_id: current_user.id })
      .where(scheduled_at: day)
      .where(status: :pending)
      .order(:scheduled_at)

    render json: occurrences.map { |occ|
      {
        id: occ.id,
        title: occ.reminder.title,
        description: occ.reminder.notes || "",
        scheduled_at: occ.scheduled_at,
        acknowledged_at: (occ.status == "acknowledged" ? occ.updated_at : nil),
        snoozed_until: nil
      }
    }
  end

  private

  # A caregiver reaching this page has nothing to hear: the reminders belong to
  # the person being cared for. The redirect is kept from the original rather
  # than a 403, because a caregiver arriving here has made a navigation mistake,
  # not an authorisation attempt.
  def care_receivers_only!
    return if current_user.role_senior?

    redirect_to dashboard_path, alert: "Voice reminders are only available for care receivers"
  end
end
