require "rails_helper"

RSpec.describe MagicMailer, type: :mailer do
  describe "#magic_link_email" do
    let(:user) { create(:user, email: "signin@example.com") }
    let(:mail) { described_class.magic_link_email(user, "tok-123") }

    it "sends to the user" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes the sign-in link in the body" do
      expect(mail.body.encoded).to include("/magic/verify")
    end

    # Gmail overrides <a> link colors set only in a <style> block, so the sign-in
    # button needs inline white text to stay legible on its blue background.
    it "gives the sign-in button inline white text" do
      expect((mail.html_part || mail.body).decoded).to match(/<a\b[^>]*class="button"[^>]*style="color: #ffffff/)
    end
  end
end
