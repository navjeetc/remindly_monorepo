require "rails_helper"

RSpec.describe SubscriberMailer, type: :mailer do
  describe "#monthly_note" do
    let(:subscriber) { Subscriber.create!(email: "ann@example.com") }
    let(:mail) { SubscriberMailer.monthly_note(subscriber) }

    it "goes to the subscriber" do
      expect(mail.to).to eq([ "ann@example.com" ])
    end

    it "sends from the one official address" do
      expect(mail.from).to eq([ ApplicationMailer::OFFICIAL_EMAIL ])
    end

    # There is still no unsubscribe link, so replying is still the only way
    # out. That has to hold on every send, not only the first.
    it "replies to a mailbox someone reads, the same as welcome" do
      expect(mail.reply_to).to eq([ SubscriberMailer::UNSUBSCRIBE_INBOX ])
    end

    it "says how to stop, since there is no unsubscribe link" do
      # /m so "." crosses the line wrap between "Reply..." and "...to stop.".
      expect(mail.text_part.body.to_s).to match(/reply.*stop/mi)
      expect(mail.html_part.body.to_s).to match(/reply.*stop/mi)
    end
  end
end
