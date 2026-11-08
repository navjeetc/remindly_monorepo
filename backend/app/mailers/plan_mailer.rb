# frozen_string_literal: true

# The one email about paid plans starting: sent once, at launch, to the
# caregivers who were using Remindly during the beta, after
# plans:grant_beta_family has given them a year of Family. See
# plans:send_launch_notice.
class PlanMailer < ApplicationMailer
  def launch_notice(user)
    @user = user

    mail(
      to: user.email,
      subject: "Remindly now has a paid plan, and you have it free for a year"
    )
  end
end
