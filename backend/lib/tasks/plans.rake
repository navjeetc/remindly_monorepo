# frozen_string_literal: true

namespace :plans do
  desc "The beta thank-you: Family free for 12 months from Plan::LAUNCHED_ON for every account " \
       "created before it. Run once, at launch. A dry run unless CONFIRM=yes. Safe to repeat: it " \
       "only ever sets the same date, and never shortens a later one."
  task grant_beta_family: :environment do
    launched_on = Plan::LAUNCHED_ON
    abort "Plan::LAUNCHED_ON is not set; paid plans have not launched." if launched_on.nil?

    granted_until = launched_on.in_time_zone("America/New_York").beginning_of_day + 12.months
    beta_users = User.where(created_at: ...launched_on.in_time_zone("America/New_York").beginning_of_day)
    due = beta_users.where(family_granted_until: nil).or(beta_users.where(family_granted_until: ...granted_until))

    unless ENV["CONFIRM"] == "yes"
      puts "Would give #{due.count} of #{beta_users.count} beta accounts Family until #{granted_until.to_date}."
      puts "Run again with CONFIRM=yes to do it."
      next
    end

    updated = due.update_all(family_granted_until: granted_until, updated_at: Time.current)
    puts "Gave #{updated} accounts Family until #{granted_until.to_date}."
  end
end
