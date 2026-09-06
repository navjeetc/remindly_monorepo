# frozen_string_literal: true

# The common case is a real relationship, so that is the default.
#
# The first cut defaulted to pending and backfilled the rest, which is right for
# the rows that existed and wrong for every row created afterwards: a link made
# by `CaregiverLink.create!` — an invitation, a factory, a console repair —
# would have been born pending and shown the caregiver a "waiting for them to
# start" panel about somebody who had been using Remindly for months.
#
# The two creators that mean something other than active say so explicitly:
# `generate_pairing_token` makes a pending row, and creating a care receiver
# makes a provisional one. Everything else is a caregiver and a care receiver
# who already have an arrangement.
class LinksAreActiveUnlessSaidOtherwise < ActiveRecord::Migration[8.1]
  def up
    change_column_default :caregiver_links, :state, from: 0, to: 2
  end

  def down
    change_column_default :caregiver_links, :state, from: 2, to: 0
  end
end
