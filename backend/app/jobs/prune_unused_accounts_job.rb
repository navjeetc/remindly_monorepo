# frozen_string_literal: true

# Deletes accounts nobody ever used.
#
# Asking for a sign-in link creates the account straight away
# (SessionsController#request_magic_link), before anyone has opened the email,
# because the link is signed for a user record. So every address typed into the
# form, by a bot, a typo, or a throwaway inbox, leaves a "No Role" account on
# Admin → Users that will never be anything else. The link is good for 30
# minutes; after that nobody can still be on their way in.
#
# Fourteen days rather than one so the Monday funnel email, which counts last
# week's new accounts in its "created" column, has counted every one of them
# before it goes. Deleting at seven would take last Monday's out of the report
# that is about them.
#
# Only accounts with nothing in them: see User.never_used. Someone who comes
# back later simply gets a new account when they ask for a link again.
class PruneUnusedAccountsJob < ApplicationJob
  queue_as :default

  GRACE = 14.days

  def perform(now: Time.current)
    User.never_used.where(created_at: ...(now - GRACE)).find_each(&:destroy)
  end
end
