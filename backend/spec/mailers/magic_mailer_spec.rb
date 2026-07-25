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

    # The link is a plain URL string, not trusted HTML — it must be rendered
    # through Rails' escaping (no html_safe), so ampersands between query params
    # come out as &amp; rather than raw & that could open an injection vector.
    it "html-escapes the link instead of trusting it as raw HTML" do
      web_mail = described_class.magic_link_email(user, "tok-123", web: true)
      body = (web_mail.html_part || web_mail.body).decoded
      expect(body).to include("&amp;next=voice_reminders")
      expect(body).not_to match(/[^;]&next=voice_reminders/)
    end
  end
end
