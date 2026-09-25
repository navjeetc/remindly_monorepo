require "rails_helper"
require "rake"

# The safety behaviour of the send task, not its content: a bare invocation
# must never deliver, only CONFIRM=yes may, and an empty list has to say so
# rather than look like it did nothing for a reason nobody can tell apart from
# working.
RSpec.describe "subscribers:send_monthly_note", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("subscribers:send_monthly_note")
  end

  # Rake::Task is a singleton across the process, unlike everything else a spec
  # touches — without this the first example's invocation is the only one that
  # ever runs, and every example after it silently exercises nothing.
  before { Rake::Task["subscribers:send_monthly_note"].reenable }

  around do |example|
    previous = ENV["CONFIRM"]
    example.run
    previous.nil? ? ENV.delete("CONFIRM") : ENV["CONFIRM"] = previous
  end

  def invoke
    Rake::Task["subscribers:send_monthly_note"].invoke
  end

  # Asserting on the printed message, not only on nothing having sent — a
  # future edit that dropped or reworded it would still pass a spec that only
  # checked for zero mail, and this line is the one thing standing between "no
  # subscribers" and "the query silently returned nothing".
  def output_of
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  context "with no subscribers" do
    it "says so and sends nothing" do
      ENV["CONFIRM"] = "yes"

      output = nil
      expect { output = output_of { invoke } }.not_to have_enqueued_mail(SubscriberMailer, :monthly_note)
      expect(output).to include("No subscribers — nothing to send.")
    end
  end

  context "with subscribers" do
    let!(:ann) { Subscriber.create!(email: "ann@example.com") }
    let!(:bo)  { Subscriber.create!(email: "bo@example.com") }

    it "sends nothing without CONFIRM=yes" do
      ENV.delete("CONFIRM")

      output = nil
      expect { output = output_of { invoke } }.not_to have_enqueued_mail(SubscriberMailer, :monthly_note)
      expect(output).to include("Would send to 2 subscribers")
      expect(output).to include(ann.email)
      expect(output).to include(bo.email)
    end

    # The exact string, not merely "something truthy". CONFIRM=1 or CONFIRM=true
    # would otherwise also fire a real send to everyone on the list, which is
    # not the deliberate second step this task is built around.
    it "sends nothing for any other value" do
      ENV["CONFIRM"] = "1"

      expect { invoke }.not_to have_enqueued_mail(SubscriberMailer, :monthly_note)
    end

    it "sends to every subscriber given CONFIRM=yes" do
      ENV["CONFIRM"] = "yes"

      expect { invoke }
        .to have_enqueued_mail(SubscriberMailer, :monthly_note).with(ann)
        .and have_enqueued_mail(SubscriberMailer, :monthly_note).with(bo)
    end

    # The bounce-suppression case the task exists to protect: a subscriber
    # MailDeliveryJob has already marked undeliverable must not be re-enqueued
    # forever, and the dry run has to say so rather than just quietly omitting
    # the address with no explanation of the missing count.
    context "when one is marked undeliverable" do
      before { ann.mark_email_undeliverable! }

      it "excludes it from the dry run and says how many were skipped" do
        ENV.delete("CONFIRM")

        output = output_of { invoke }

        expect(output).to include("Would send to 1 subscriber")
        expect(output).not_to include(ann.email)
        expect(output).to include(bo.email)
        expect(output).to include("1 more marked undeliverable, skipped")
      end

      it "does not enqueue it given CONFIRM=yes" do
        ENV["CONFIRM"] = "yes"

        expect { invoke }
          .to have_enqueued_mail(SubscriberMailer, :monthly_note).with(bo)
          .and have_enqueued_mail(SubscriberMailer, :monthly_note).with(ann).exactly(0).times
      end
    end
  end
end
