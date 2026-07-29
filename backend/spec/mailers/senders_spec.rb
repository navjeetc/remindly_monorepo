require "rails_helper"

# remindly.care has exactly one official address, and it is the only
# DKIM-verified Postmark sender. Mail from anything else is rejected outright.
#
# That is not hypothetical. notifications@remindly.app was silently rejected on
# every send until someone noticed, and the fix was applied to one mailer while
# the same invalid fallback survived in six others — where it went unnoticed
# because credentials happened to be set in production, so the fallback never
# ran. These specs fail on the next one that gets it wrong.
RSpec.describe "Mailer senders" do
  OFFICIAL = "hello@remindly.care".freeze

  MAILER_ROOT = Rails.root.join("app/mailers")

  # Recursive, and the constant is derived from the path rather than the
  # basename, so a namespaced mailer (app/mailers/admin/foo_mailer.rb ->
  # Admin::FooMailer) is checked rather than skipped. Globbing only the top
  # level meant a mailer in a subdirectory bypassed the sender guard entirely
  # while the other checks in this file already looked recursively.
  def mailers
    MAILER_ROOT.glob("**/*.rb").map { |path|
      path.relative_path_from(MAILER_ROOT).to_s.delete_suffix(".rb").camelize.constantize
    }.select { |klass| klass < ActionMailer::Base }
  end

  it "finds the mailers, so an empty list cannot pass silently" do
    expect(mailers.size).to be >= 6
  end

  # Parses the header rather than substring-matching it. `include?` passes on
  # "Remindly <hello@remindly.care>, attacker@evil.example" — the official
  # address is present, and so is a second one. The point of this spec is that
  # there is exactly one sender, so it has to assert exactly one.
  it "sends everything from the one official address, and only that" do
    mailers.each do |mailer|
      raw = Array(mailer.default[:from]).join(", ")
      addresses = Mail::AddressList.new(raw).addresses.map(&:address)

      expect(addresses).to eq([ OFFICIAL ]), "#{mailer} sends from #{raw.inspect}"
    end
  end

  # The value being right everywhere is not the same as it being defined once.
  # Two mailers had already been corrected by hand and agreed with the new
  # default by coincidence — which is exactly the state that let six others
  # drift without anyone noticing. A second definition is a second thing to
  # remember, so ApplicationMailer is the only place allowed to set it.
  it "declares the sender in exactly one place" do
    definers = Rails.root.glob("app/mailers/**/*.rb").select { |path|
      path.read.lines.any? { |line| line.match?(/^\s*default from:/) }
    }.map { |path| path.basename.to_s }

    expect(definers).to eq([ "application_mailer.rb" ])
  end

  # The domain that was rejected on every send. Nothing may use it again, in a
  # sender, a recipient, or a fallback.
  #
  # Comment lines are skipped deliberately: the history of this bug is recorded
  # in comments in two mailers, and that record is worth keeping. It is the code
  # that must not name the domain.
  it "uses the unverified remindly.app domain nowhere" do
    offenders = Rails.root.glob("app/mailers/**/*.rb").select { |path|
      path.read.lines.any? { |line| line.match?(/@remindly\.app/) && !line.strip.start_with?("#") }
    }.map { |path| path.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty,
      "remindly.app is not a confirmed sender and mail using it is rejected:\n  #{offenders.join("\n  ")}"
  end

  # The sender and the recipient are different problems, and conflating them
  # was a real mistake here: hardcoding the recipient alongside the sender
  # silently redirected contact-form submissions away from whichever inbox a
  # deployment had configured to receive them.
  #
  # The From address must be the one verified sender or Postmark rejects the
  # message. Who hears about a contact form is a deployment's choice.
  describe "mail addressed to us" do
    around do |example|
      original = ENV["ADMIN_EMAIL"]
      example.run
      ENV["ADMIN_EMAIL"] = original
    end

    it "honours a configured admin address" do
      allow(Rails.application.credentials).to receive(:admin_email).and_return("support@example.com")

      expect(ApplicationMailer.admin_recipient).to eq("support@example.com")
    end

    it "honours ADMIN_EMAIL when no credential is set" do
      allow(Rails.application.credentials).to receive(:admin_email).and_return(nil)
      ENV["ADMIN_EMAIL"] = "ops@example.com"

      expect(ApplicationMailer.admin_recipient).to eq("ops@example.com")
    end

    # Only the fallback changed. It used to be the invalid admin@remindly.app.
    it "falls back to the official address rather than an unverified one" do
      allow(Rails.application.credentials).to receive(:admin_email).and_return(nil)
      ENV.delete("ADMIN_EMAIL")

      expect(ApplicationMailer.admin_recipient).to eq(OFFICIAL)
    end

    it "routes contact submissions to the configured address" do
      allow(Rails.application.credentials).to receive(:admin_email).and_return("support@example.com")

      mail = ContactMailer.contact_form_submission(name: "Ann", email: "ann@example.com", description: "Hello")

      expect(mail.to).to eq([ "support@example.com" ])
      expect(mail.from).to eq([ OFFICIAL ])
    end

    it "routes new-subscriber notices to the configured address" do
      allow(Rails.application.credentials).to receive(:admin_email).and_return("support@example.com")

      mail = SubscriberMailer.new_subscriber(Subscriber.create!(email: "ann@example.com"))

      expect(mail.to).to eq([ "support@example.com" ])
      expect(mail.from).to eq([ OFFICIAL ])
    end
  end

  # admin_email is a personal address on a different domain. Product mail should
  # come from the product, and several mailers were using it as their From.
  it "does not fall back to the personal admin credential for the sender" do
    offenders = Rails.root.glob("app/mailers/**/*.rb").select { |path|
      path.read.match?(/default from:.*credentials\.admin_email/)
    }.map { |path| path.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty, "sender should be the product address:\n  #{offenders.join("\n  ")}"
  end
end
