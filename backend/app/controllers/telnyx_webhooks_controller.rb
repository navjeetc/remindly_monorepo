# Receives Call Control events from Telnyx as an outbound call progresses.
#
# The URL configured in the Telnyx portal must include the shared token:
#   https://example.com/telnyx/webhooks?token=...
#
# Event flow:
#   call.answered        -> gather_using_speak: announce the reminder and wait for a digit
#   call.gather.ended    -> record the digit and acknowledge the dose
#   call.hangup          -> if no digit, mark as no_response
#
# Each event carries a `call_control_id` that maps to a TelnyxCall record,
# and a `client_state` that maps back to the occurrence and senior.
class TelnyxWebhooksController < ApplicationController
  before_action :verify_webhook

  def receive
    event = webhook_event
    return head :bad_request unless event

    event_type = event["event_type"]
    payload = event["payload"] || {}
    event_id = event["id"]

    call_control_id = payload["call_control_id"]
    call = TelnyxCall.find_by(call_control_id: call_control_id)

    unless call
      # A dial that the provider accepted can produce a callback before dial()
      # has written call_control_id back. Answering 200 to that would retire the
      # event for good — and if the lost event is call.answered, the senior is
      # connected to a call that never speaks.
      #
      # client_state tells us whether it is ours: it carries the occurrence this
      # call was placed for. If it names an occurrence we hold, ask for a retry
      # and the reservation will have caught up by then. If it names nothing we
      # recognise, the event genuinely is not ours and retrying it forever would
      # be its own bug.
      if ours?(event)
        Rails.logger.warn "Telnyx webhook for a call not yet correlated, asking for retry: #{call_control_id}"
        return head :internal_server_error
      end

      Rails.logger.warn "Telnyx webhook for unknown call: #{call_control_id}"
      return head :ok
    end

    call.update!(last_payload: event.to_json, status: status_from_event(event_type))

    case event_type
    when "call.answered"
      handle_answered(call, event_id)
    when "call.gather.ended"
      handle_gather_ended(call, payload, event_id)
    when "call.hangup"
      handle_hangup(call)
    end

    head :ok
  rescue => e
    Rails.logger.error "Telnyx webhook #{event_type} failed for #{call_control_id}: #{e.full_message}"

    # 500, so Telnyx retries. A 200 here would tell the provider the keypress
    # was handled and it would never send it again: the senior pressed 1, the
    # write failed, the acknowledgement is gone, the occurrence stays pending,
    # and the caregiver is eventually emailed that she never marked it done.
    # Every handler below is idempotent, so a retry is safe.
    head :internal_server_error
  end

  private

  def verify_webhook
    head :unauthorized unless TelnyxVoiceService.webhook_valid?(request)
  end

  # The gather is issued before answered_at is recorded, and the order is the
  # whole point. Recording first made a failed gather permanent: the flag
  # suppressed the retry, `receive` answered 200, and the senior sat listening
  # to silence with no second chance. Doing it this way leaves the event
  # unhandled and redeliverable when the provider call fails.
  #
  # Gathering twice is safe. command_id is Telnyx's idempotency key and this
  # passes the webhook's own event id, so a redelivered event issues the same
  # command and the provider discards the duplicate rather than speaking twice.
  def handle_answered(call, event_id)
    return if call.answered_at.present?

    occurrence = call.occurrence
    reminder = occurrence.reminder
    senior = call.user

    TelnyxVoiceService.gather_digit(
      call_control_id: call.call_control_id,
      prompt: announcement_for(senior, reminder),
      command_id: event_id
    )

    call.update!(answered_at: Time.current)
  end

  # Reminder titles are free text and most of them are imperative phrases
  # ("Take meds", "Drink water"), so the title cannot sit inside a clause. The
  # earlier wording -- "this is your #{title} reminder" -- put "your" directly
  # in front of an imperative, and a listener hears that as a different sentence
  # than the one that was sent. Giving the title a sentence of its own reads
  # correctly whichever part of speech it turns out to be.
  #
  # Naming Remindly in the first breath is deliberate. An automated voice
  # telling an older person to do something and press a key is the shape of the
  # scams this demographic is warned about, and the opening seconds are the only
  # mitigation that works -- CNAM does not survive most mobile carriers.
  #
  # "done it" rather than "taken it" because a reminder is not always a dose:
  # you do not take a glass of water or a walk.
  def announcement_for(senior, reminder)
    task = reminder.title.to_s.strip.sub(/[.!?,;:]+\z/, "")

    "Hello #{senior.display_name}. This is Remindly, with your reminder. " \
    "#{task}. " \
    "Press 1 if you have done it. " \
    "Press 2 to be reminded again in #{Occurrence::SNOOZE_DEFAULT_MINUTES} minutes."
  end

  def handle_gather_ended(call, payload, event_id)
    digits = payload["digits"]

    if call.outcome == "pending"
      call.update!(dtmf: digits, status: "completed")

    case digits
    when "1"
      acknowledge!(call, "taken")
    when "2"
      snooze!(call)
    else
      # Unrecognized digit; treat as no response and hang up.
      call.update!(outcome: "no_response")
    end

      # Enqueued on every delivery of this event, not only the one that won the
      # acknowledgement. The previous shape conditioned it on first_ack from the
      # transaction that had already committed, so if enqueueing failed — or the
      # process died — a redelivery found outcome == "taken", took the early
      # return above, and the caregiver was never told. Both this job and the
      # per-caregiver delivery beneath it are idempotent, and the job re-reads the
      # occurrence status before sending, so enqueueing twice costs nothing.
    end

    ReminderNotificationJob.perform_later(call.occurrence_id, "acknowledged") if call.outcome == "taken"

    # If the gather ended because the caller hung up, the call is already gone.
    unless payload["status"] == "call_hangup"
      TelnyxVoiceService.hangup(call_control_id: call.call_control_id, command_id: event_id)
    end
  end

  def handle_hangup(call)
    return if call.outcome != "pending"

    call.update!(outcome: "no_response", completed_at: Time.current)
  end

  # Deliberately no rescue: a failure here must propagate so `receive` answers
  # non-2xx and Telnyx sends the event again. Safe to retry — the guard below
  # and the compare-and-swap on the occurrence both make a repeat a no-op.
  def acknowledge!(call, kind)
    return unless call.outcome == "pending"

    ActiveRecord::Base.transaction do
      # Compare-and-swap, so the affected-row count decides whether this request
      # is the one that resolved the occurrence — the same handshake the web
      # client uses, and what makes a late take able to correct a row the missed
      # sweep already claimed. The caregiver notification no longer hangs off
      # this result; it is enqueued by the caller on every delivery, because
      # a value computed inside a committed transaction cannot tell a retry
      # whether the work after the commit ever happened.
      first_ack = Occurrence.where(id: call.occurrence_id)
                            .where.not(status: :acknowledged)
                            .update_all(status: Occurrence.statuses[:acknowledged], updated_at: Time.current)
                            .positive?

      Acknowledgement.create!(occurrence_id: call.occurrence_id, kind: kind, at: Time.current) if first_ack

      call.update!(outcome: kind, completed_at: Time.current)
    end
  end

  # Snoozing writes the acknowledgement AND schedules the next occurrence, which
  # is why it goes through the model rather than acknowledge!: recording the kind
  # alone would resolve the reminder and never bring it back, so pressing 2 would
  # quietly cancel the dose it was meant to postpone.
  def snooze!(call)
    return unless call.outcome == "pending"

    later = call.occurrence.snooze!
    call.update!(outcome: "snooze", completed_at: Time.current)
    Rails.logger.info "Voice snooze for call #{call.call_control_id}: next occurrence #{later.id} at #{later.scheduled_at}"
  end

  # Whether this event belongs to a call we placed, decided from client_state
  # rather than from the call id we have not managed to record yet.
  def ours?(event)
    state = event.dig("payload", "client_state")
    return false if state.blank?

    occurrence_id = JSON.parse(Base64.decode64(state))["occurrence_id"]
    occurrence_id.present? && Occurrence.exists?(id: occurrence_id)
  rescue JSON::ParserError, ArgumentError => e
    Rails.logger.warn "Telnyx webhook client_state unreadable: #{e.message}"
    false
  end

  def webhook_event
    params["data"] || params.dig("metadata", "event")
  end

  def status_from_event(event_type)
    case event_type
    when "call.initiated" then "initiated"
    when "call.answered" then "answered"
    when "call.gather.ended" then "gathering"
    when "call.hangup" then "hangup"
    else "completed"
    end
  end
end
