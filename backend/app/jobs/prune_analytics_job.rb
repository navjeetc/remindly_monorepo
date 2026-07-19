# Deletes old analytics rows.
#
# Ahoy.visitor_duration only controls how long the visitor cookie lives; nothing
# removes the rows. Visits store an IP address and user agent, so without this
# they accumulate indefinitely — the oldest in production when this was written
# was 270 days old.
#
# Ninety days is long enough to compare against a previous quarter and short
# enough that an address is not kept for years to record that someone once
# visited.
class PruneAnalyticsJob < ApplicationJob
  queue_as :default

  RETENTION = 90.days

  def perform(retention: RETENTION)
    cutoff = retention.ago

    # An undated row counts as expired. started_at and time are both nullable, so
    # a row with no timestamp would otherwise never match a "before the cutoff"
    # filter and would keep its IP address indefinitely — which is exactly what
    # this job exists to prevent. There is no version of "recent enough to keep"
    # that a row without a date can satisfy.
    expired_visits = Ahoy::Visit.where(started_at: ...cutoff).or(Ahoy::Visit.where(started_at: nil))

    # Events go by three rules: older than the cutoff, undated, or belonging to a
    # visit that is about to go. An event records its own time, so a recent event
    # attached to an expired visit would otherwise survive and point at a row
    # that no longer exists.
    events = Ahoy::Event
      .where(time: ...cutoff)
      .or(Ahoy::Event.where(time: nil))
      .or(Ahoy::Event.where(visit_id: expired_visits.select(:id)))
      .delete_all

    visits = expired_visits.delete_all

    Rails.logger.info(
      "PruneAnalyticsJob: removed #{visits} visits and #{events} events " \
      "(before #{cutoff.to_date}, undated, or attached to a removed visit)"
    )

    { visits: visits, events: events }
  end
end
