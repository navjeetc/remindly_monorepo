require "rails_helper"

RSpec.describe SubscriberMailer, type: :mailer do
  let(:subscriber) { Subscriber.create!(email: "ann@example.com") }

  # Shared between welcome and monthly_note: both promise a way to stop, both
  # now carry a real link as well as the reply-to fallback, and a regression
  # in one is exactly as bad as in the other.
  shared_examples "an email that can be unsubscribed from" do
    it "replies to a mailbox someone reads" do
      expect(mail.reply_to).to eq([ SubscriberMailer::UNSUBSCRIBE_INBOX ])
    end

    it "still offers replying, alongside the link" do
      expect(mail.text_part.body.to_s).to match(/reply.*stop/mi)
      expect(mail.html_part.body.to_s).to match(/reply.*stop/mi)
    end

    # The token has to name *this* subscriber and *this* purpose — a generic
    # or shared link would let one person's email unsubscribe somebody else,
    # or be reusable for something a signed_id was never meant to authorise.
    it "carries a working unsubscribe link, unique to this subscriber" do
      expected_token = subscriber.signed_id(purpose: :unsubscribe)

      expect(mail.text_part.body.to_s).to include("/subscribers/unsubscribe/#{expected_token}")

      html_link = Nokogiri::HTML(mail.html_part.body.to_s).at_css("a[href*='/subscribers/unsubscribe/']")
      expect(html_link).to be_present
      expect(html_link["href"]).to end_with("/subscribers/unsubscribe/#{expected_token}")
    end

    # Proof the token actually authenticates, not just that it looks like a
    # link — extract it from the rendered mail and resolve it the same way
    # SubscribersController does. The full request round trip lives in
    # subscribers_unsubscribe_spec.rb, which has the HTTP helpers this
    # example group does not.
    it "carries a token that actually resolves back to this subscriber" do
      html_link = Nokogiri::HTML(mail.html_part.body.to_s).at_css("a[href*='/subscribers/unsubscribe/']")
      token = html_link["href"].split("/").last

      expect(Subscriber.find_signed(token, purpose: :unsubscribe)).to eq(subscriber)
    end
  end

  describe "#monthly_note" do
    let(:mail) { SubscriberMailer.monthly_note(subscriber) }

    it "goes to the subscriber" do
      expect(mail.to).to eq([ "ann@example.com" ])
    end

    it "sends from the one official address" do
      expect(mail.from).to eq([ ApplicationMailer::OFFICIAL_EMAIL ])
    end

    include_examples "an email that can be unsubscribed from"
  end

  describe "#welcome" do
    let(:mail) { SubscriberMailer.welcome(subscriber) }

    it "goes to the subscriber" do
      expect(mail.to).to eq([ "ann@example.com" ])
    end

    include_examples "an email that can be unsubscribed from"
  end
end
