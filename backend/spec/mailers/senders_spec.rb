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

  def mailers
    Rails.root.glob("app/mailers/*.rb").map { |path|
      path.basename(".rb").to_s.camelize.constantize
    }.select { |klass| klass < ActionMailer::Base }
  end

  it "finds the mailers, so an empty list cannot pass silently" do
    expect(mailers.size).to be >= 6
  end

  it "sends everything from the one official address" do
    mailers.each do |mailer|
      from = Array(mailer.default[:from]).join

      expect(from).to include(OFFICIAL), "#{mailer} sends from #{from.inspect}"
    end
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

  # admin_email is a personal address on a different domain. Product mail should
  # come from the product, and several mailers were using it as their From.
  it "does not fall back to the personal admin credential for the sender" do
    offenders = Rails.root.glob("app/mailers/**/*.rb").select { |path|
      path.read.match?(/default from:.*credentials\.admin_email/)
    }.map { |path| path.relative_path_from(Rails.root).to_s }

    expect(offenders).to be_empty, "sender should be the product address:\n  #{offenders.join("\n  ")}"
  end
end
