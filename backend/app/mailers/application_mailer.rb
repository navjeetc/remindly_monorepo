class ApplicationMailer < ActionMailer::Base
  # The one official address for remindly.care, and the only DKIM-verified
  # Postmark sender. Mail from anything else is rejected outright — that is not
  # theoretical: notifications@remindly.app was silently rejected on every send
  # until someone noticed, and the same invalid remindly.app fallback then
  # survived in six mailers. It is defined once here so there is nowhere left
  # for a second sender to hide.
  #
  # Deliberately not read from credentials. admin_email is navjeet@anakhsoft.com
  # — a personal address on a different domain, which several mailers were using
  # as their From. Product mail should come from the product.
  OFFICIAL_EMAIL = "hello@remindly.care".freeze
  BRANDED_SENDER = "Remindly <#{OFFICIAL_EMAIL}>".freeze

  default from: BRANDED_SENDER
  layout "mailer"
end
