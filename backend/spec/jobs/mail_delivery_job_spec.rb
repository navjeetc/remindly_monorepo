require "rails_helper"

RSpec.describe MailDeliveryJob do
  let(:user) { create(:user, :caregiver, email: "gone@example.com") }
  let(:subscriber) { Subscriber.create!(email: "reader@example.com") }

  # Built the way the gem builds it — from an API response, with the addresses
  # living in parsed_body["Message"] rather than in the exception string. The
  # first version of this spec passed a bare message and got an error with no
  # recipients, which is the same mistake the job would make if it parsed the
  # text itself instead of reading `recipients`.
  def inactive_error(*addresses)
    message =
      "You tried to send to recipient(s) that have been marked as inactive. " \
      "Found inactive addresses: #{addresses.join(', ')}. Inactive recipients are ones that " \
      "have generated a hard bounce or a spam complaint."

    Postmark::InactiveRecipientError.new(
      Postmark::ApiInputError::INACTIVE_RECIPIENT,
      message,
      { "ErrorCode" => Postmark::ApiInputError::INACTIVE_RECIPIENT, "Message" => message }
    )
  end

  # Stub the instance, not any_instance: if the stub ever fails to apply, the
  # real perform runs and the failure says so plainly.
  def job_raising(error)
    described_class.new("SubscriberMailer", "welcome", "deliver_now", args: [ subscriber ]).tap do |job|
      allow(job).to receive(:perform).and_raise(error)
    end
  end

  it "is the job Rails uses for deliver_later" do
    expect(ActionMailer::Base.delivery_job).to eq(described_class)
  end

  it "reads the refused addresses off the error" do
    expect(inactive_error("a@example.com", "b@example.com").recipients)
      .to contain_exactly("a@example.com", "b@example.com")
  end

  describe "when Postmark permanently refuses the recipient" do
    # Retrying cannot help — Postmark decided on evidence from the receiving
    # server, and the gem's own `retry?` returns false for this class. A retry
    # that ends in FailedExecution is how 44 of these piled up unnoticed.
    it "discards the job instead of retrying it" do
      expect { job_raising(inactive_error(user.email)).perform_now }.not_to raise_error
    end

    it "records the address as undeliverable" do
      expect { job_raising(inactive_error(user.email)).perform_now }
        .to change { user.reload.email_undeliverable_at }.from(nil)

      expect(user.reload).not_to be_email_deliverable
    end

    it "marks every address the error names" do
      other = create(:user, :caregiver, email: "also-gone@example.com")

      job_raising(inactive_error(user.email, other.email)).perform_now

      expect(user.reload.email_undeliverable_at).to be_present
      expect(other.reload.email_undeliverable_at).to be_present
    end

    # An address Postmark refuses need not belong to a user — a subscriber, or
    # an account since deleted. Discarding must still work.
    it "survives an address with no matching user" do
      expect { job_raising(inactive_error("stranger@example.com")).perform_now }.not_to raise_error
    end

    # The date of the first refusal is the useful one when someone asks why they
    # stopped hearing from us; a later bounce should not move it.
    it "keeps the first refusal date" do
      job_raising(inactive_error(user.email)).perform_now
      first = user.reload.email_undeliverable_at
      expect(first).to be_present

      # An explicit later time rather than time travel: two calls in the same
      # millisecond would record the same timestamp and the test would pass
      # whether or not the guard exists.
      user.reload.mark_email_undeliverable!(at: 1.day.from_now)

      expect(user.reload.email_undeliverable_at).to eq(first)
    end
  end

  # Everything else still deserves Rails' retry behaviour: a timeout or a 500
  # from Postmark is exactly what retries exist for.
  it "does not swallow ordinary delivery failures" do
    expect { job_raising(Net::OpenTimeout).perform_now }.to raise_error(Net::OpenTimeout)
  end
end
