# frozen_string_literal: true

require "rails_helper"

RSpec.describe Occurrence do
  let(:senior) { create(:user, :senior, :takes_calls, name: "Mom") }
  let(:reminder) { Reminder.create!(user: senior, title: "Metformin", category: :medication, rrule: "FREQ=DAILY", tz: senior.tz) }
  let(:occurrence) { Occurrence.create!(reminder: reminder, scheduled_at: Time.zone.local(2026, 7, 21, 9, 0), status: :pending) }

  # What a refusal is allowed to say about somebody.
  #
  # The caregiver email branches on the reason, and a reason it does not know
  # borrows the sentence written for a different one -- twice now, the one that
  # reports a non-event as her lapse. So an unknown reason is refused at the
  # write rather than left for the email to interpret.
  describe "#suppress_call!" do
    it "records a reason the email has a branch for" do
      occurrence.suppress_call!(:outside_calling_hours)

      expect(occurrence.reload.call_suppressed_reason).to eq("outside_calling_hours")
      expect(occurrence.call_suppressed_at).to be_present
    end

    # The message names the two things the next person has to do, because the
    # failure is otherwise a mystery at three in the morning.
    it "refuses a reason nothing knows how to explain" do
      expect { occurrence.suppress_call!(:mystery) }
        .to raise_error(ArgumentError, /PHONE_FAILURE_REASONS.*branch/m)
    end

    it "leaves the row alone when it refuses" do
      expect { occurrence.suppress_call!(:mystery) }.to raise_error(ArgumentError)

      expect(occurrence.reload.call_suppressed_at).to be_nil
      expect(occurrence.call_suppressed_reason).to be_nil
    end

    # nil is what a caller passes when it has worked out a reason and got
    # nothing. It must not be written either: phone_failure_reason reads a blank
    # reason as "no story here", so a suppressed row carrying one would go back
    # to being reported as her failing.
    it "refuses nothing at all" do
      expect { occurrence.suppress_call!(nil) }.to raise_error(ArgumentError)
    end
  end
end
