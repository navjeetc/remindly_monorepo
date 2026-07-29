class ApplicationMailer < ActionMailer::Base
  # The one official address for remindly.care, and the only DKIM-verified
  # Postmark sender. Mail from anything else is rejected outright — that is not
  # theoretical: notifications@remindly.app was silently rejected on every send
  # until someone noticed, and the same invalid remindly.app fallback then
  # survived in six mailers. Two others had been corrected by hand and happened
  # to agree, which is not the same as being right — it is the state that let
  # the other six drift unnoticed. This is now the only place allowed to set a
  # sender, and senders_spec fails on any mailer that declares its own.
  #
  # Deliberately not read from credentials. admin_email is navjeet@anakhsoft.com
  # — a personal address on a different domain, which several mailers were using
  # as their From. Product mail should come from the product.
  OFFICIAL_EMAIL = "hello@remindly.care".freeze
  BRANDED_SENDER = "Remindly <#{OFFICIAL_EMAIL}>".freeze

  default from: BRANDED_SENDER
  layout "mailer"

  # Where mail *to us* goes — contact submissions, new-subscriber notices.
  #
  # Deliberately still configurable, unlike the sender above. The two are
  # different problems that got conflated: the From address has to be the one
  # verified sender or Postmark rejects the message, but the recipient is a
  # deployment's choice about who handles support, and hardcoding it silently
  # redirected contact submissions away from the inbox someone was watching.
  #
  # Only the fallback changed, from the invalid admin@remindly.app.
  def self.admin_recipient
    Rails.application.credentials.admin_email || ENV.fetch("ADMIN_EMAIL", OFFICIAL_EMAIL)
  end
end
