# frozen_string_literal: true

namespace :plans do
  desc "The beta thank-you: Family free for 12 months from Plan::LAUNCHED_ON for every account " \
       "created by the end of that day. Done at deploy by a migration; this repeats it. A dry run unless CONFIRM=yes. Safe to repeat: it " \
       "only ever sets the same date, and never shortens a later one."
  task grant_beta_family: :environment do
    launched_on = Plan::LAUNCHED_ON
    abort "Plan::LAUNCHED_ON is not set; paid plans have not launched." if launched_on.nil?

    # The deploy's migration (GrantTheBetaYear) did this already; this task is
    # the repair if it ever needs doing again.
    granted_until = Plan.beta_year_until
    beta_users = User.where(created_at: ..Plan.beta_year_cutoff)
    due = beta_users.where(family_granted_until: nil).or(beta_users.where(family_granted_until: ...granted_until))

    unless ENV["CONFIRM"] == "yes"
      puts "Would give #{due.count} of #{beta_users.count} beta accounts Family until #{granted_until.to_date}."
      puts "Run again with CONFIRM=yes to do it."
      next
    end

    updated = due.update_all(family_granted_until: granted_until, updated_at: Time.current)
    puts "Gave #{updated} accounts Family until #{granted_until.to_date}."
  end

  desc "Email the caregivers given the beta year that paid plans have started. Run once, after " \
       "grant_beta_family. A dry run unless CONFIRM=yes. Not idempotent: a second run sends again."
  task send_launch_notice: :environment do
    # Caregivers only: the Plan page is theirs, and a care receiver's plan
    # follows the best in their circle. Only those given the year, so nobody
    # is told about a gift they do not have.
    recipients = User.role_caregiver.deliverable.where.not(email: [ nil, "" ])
                     .where(family_granted_until: Time.current..)
    count = recipients.count

    unless ENV["CONFIRM"] == "yes"
      puts "Would send to #{count} #{'caregiver'.pluralize(count)}:"
      recipients.order(:created_at).each { |user| puts "  #{user.email}" }
      puts ""
      puts "Nothing has been sent. Review app/views/plan_mailer/launch_notice.*, then run with CONFIRM=yes."
      next
    end

    # deliver_later, for the reason subscribers:send_monthly_note gives: one
    # refused address must not stop everyone after it.
    recipients.find_each { |user| PlanMailer.launch_notice(user).deliver_later }
    puts "Queued #{count} #{'email'.pluralize(count)}."
  end
end
