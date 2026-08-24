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
    call = TelnyxCall.find_by(call_control_id: call_control_id) || correlate(event, call_control_id)

    unless call
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

    return handle_verification_answered(call, event_id) if call.purpose == "verification"

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
    return handle_verification_gather_ended(call, payload, event_id) if call.purpose == "verification"

    digits = payload["digits"]

    if call.outcome == "pending"
      call.update!(dtmf: digits, status: "completed")

      case digits
      when "1"
        acknowledge!(call, "taken")
      when "2"
        snooze!(call)
      else
        # No digit, or one we do not offer. The call is finished either way, so
        # record that here rather than leaving it to the hangup event — which
        # used to skip it, because by then the outcome was no longer pending.
        call.update!(outcome: "no_response", completed_at: Time.current)
      end
    end

    # Deliberately outside the guard above, and enqueued on every delivery of
    # this event rather than only on the one that won the acknowledgement. The
    # previous shape conditioned it on first_ack from the transaction that had
    # already committed, so if enqueueing failed — or the process died — a
    # redelivery found outcome == "taken", skipped the block above, and the
    # caregiver was never told. Both this job and the per-caregiver delivery
    # beneath it are idempotent, and the job re-reads the occurrence status
    # before sending, so enqueueing twice costs nothing.
    ReminderNotificationJob.perform_later(call.occurrence_id, "acknowledged") if call.outcome == "taken"

    # If the gather ended because the caller hung up, the call is already gone.
    unless payload["status"] == "call_hangup"
      TelnyxVoiceService.hangup(call_control_id: call.call_control_id, command_id: event_id)
    end
  end

  # The call is over. That is a fact regardless of what was pressed, so
  # completed_at is recorded unconditionally: an attempt that has ended is not
  # still occupying the line, and TelnyxCall.call_in_flight? decides whether
  # this senior may be called again by reading exactly that column. Leaving it
  # nil made a finished call block the next one for the whole in-flight window.
  #
  # Only the outcome is conditional — a keypress already resolved it, and a
  # hangup arriving afterwards must not overwrite what the senior said.
  def handle_hangup(call)
    attributes = { completed_at: call.completed_at || Time.current }
    attributes[:outcome] = "no_response" if call.outcome == "pending"

    call.update!(attributes)
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

  # The verification call. Asks whether this number agrees to be telephoned at
  # all, and is the only thing in the application permitted to answer yes.
  def handle_verification_answered(call, event_id)
    TelnyxVoiceService.gather_digit(
      call_control_id: call.call_control_id,
      prompt: consent_request_for(call.user),
      command_id: event_id
    )

    call.update!(answered_at: Time.current)
  end

  # Named for the caregiver who arranged it, in the first breath, because that is
  # the one thing a stranger calling out of the blue could not know. What we will
  # never ask for comes before what we are asking for, since every telephone scam
  # wants information and saying we do not want any is the clearest signal
  # available in the seconds before somebody hangs up.
  #
  # An earlier draft promised never to ask for money. It was cut: Remindly may be
  # monetised, and a promise made in a recorded call to an elderly person is not
  # one to walk back. "All you ever need to do is press a button" does the same
  # work, survives any business model because it is a promise about calls rather
  # than about pricing, and sets the expectation for every later call too.
  def consent_request_for(senior)
    arranger = senior.caregivers.first

    "Hello. This is Remindly, calling for #{senior.display_name}. " \
    "#{arranger ? "#{arranger.friendly_name} asked us" : "You asked us"} to phone you with reminders — " \
    "for example, when it is time to take your tablets. " \
    "We will never ask you for personal details. All you ever need to do is press a button. " \
    "If you would like these reminders, press 1 now. " \
    "If you would rather not, press 9 and we will not call again."
  end

  def handle_verification_gather_ended(call, payload, event_id)
    if call.outcome == "pending"
      digits = payload["digits"]
      call.update!(dtmf: digits, status: "completed")

      case digits
      when "1" then consent!(call)
      when "9" then opt_out!(call)
      else
        # No digit, or one we do not offer. Not consent — and deliberately not an
        # opt-out either: someone who said nothing has not said stop, and burning
        # their opt-out on a silence would take away the one thing that is
        # supposed to be theirs to say.
        call.update!(outcome: "declined", completed_at: Time.current)
      end
    end

    hang_up_unless_already_gone(call, payload, event_id)
  end

  # The only writer of call_reminders_enabled in the application. Everything else
  # reads it.
  def consent!(call)
    senior = call.user

    ActiveRecord::Base.transaction do
      senior.update!(
        phone_verified_at: Time.current,
        call_consent_at: Time.current,
        call_opted_out_at: nil,
        call_reminders_enabled: true
      )
      call.update!(outcome: "consented", completed_at: Time.current)
    end
  end

  # Immediate and permanent, per the design document, and available on every call
  # rather than only this one. The senior may have no other interface at all, so
  # the keypad is their only way to say stop; requiring them to ask the caregiver
  # who arranged the calls inverts the relationship this is supposed to respect.
  def opt_out!(call)
    senior = call.user

    ActiveRecord::Base.transaction do
      senior.update!(call_opted_out_at: Time.current, call_reminders_enabled: false)
      call.update!(outcome: "opted_out", completed_at: Time.current)
    end
  end

  def hang_up_unless_already_gone(call, payload, event_id)
    return if payload["status"] == "call_hangup"

    TelnyxVoiceService.hangup(call_control_id: call.call_control_id, command_id: event_id)
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

  # Adopt a reserved attempt whose call_control_id never got written back.
  #
  # dial() can fail to persist the id after Telnyx has already accepted the
  # call — its rescue marks the attempt failed and the id is lost with it.
  # Asking for a retry does not recover that: nothing else correlates the
  # event, so every redelivery takes the same branch until the provider gives
  # up, and the senior stays connected to a call that never speaks. The event
  # itself carries enough to repair the link, because client_state names the
  # occurrence the call was placed for.
  def correlate(event, call_control_id)
    state = client_state(event)
    occurrence_id = state["occurrence_id"]
    attempt_number = state["attempt_number"]

    # Both, or nothing. Matching on occurrence alone means picking the most
    # recent uncorrelated row, and a delayed callback from attempt 1 then
    # attaches to attempt 2 — whose own dial later overwrites the id while
    # leaving answered_at set, so attempt 2's real call.answered is skipped and
    # that senior hears silence. Guessing is worse than declining to correlate.
    return nil if occurrence_id.blank? || attempt_number.blank?

    # Conditional claim rather than find-then-write: two deliveries of the same
    # event race here too, and the row must be taken exactly once.
    claimed = TelnyxCall.where(occurrence_id: occurrence_id, attempt_number: attempt_number, call_control_id: nil)
                        .update_all(call_control_id: call_control_id, status: "initiated",
                                    outcome: "pending", completed_at: nil, updated_at: Time.current)

    attempt = TelnyxCall.find_by(call_control_id: call_control_id)
    Rails.logger.info "Telnyx webhook correlated #{call_control_id} to attempt #{attempt&.id}" if claimed.positive?
    attempt
  rescue ActiveRecord::RecordNotUnique
    # Another delivery correlated it first.
    TelnyxCall.find_by(call_control_id: call_control_id)
  end

  def client_state(event)
    encoded = event.dig("payload", "client_state")
    return {} if encoded.blank?

    parsed = JSON.parse(Base64.decode64(encoded))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, ArgumentError => e
    Rails.logger.warn "Telnyx webhook client_state unreadable: #{e.message}"
    {}
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
