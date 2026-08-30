# frozen_string_literal: true

class NormalizeUserTimezones < ActiveRecord::Migration[8.1]
  # The tz column had drifted into holding two different spellings of the same
  # thing: IANA identifiers ("America/New_York", which is the column default)
  # and Rails zone names ("Eastern Time (US & Canada)", which is what the
  # profile form used to submit). Nothing ever failed on it, because every read
  # goes through ActiveSupport::TimeZone[] and that accepts either — which is
  # why the mixture survived unnoticed. User#tz= now settles on the identifier;
  # this brings the rows already written into line with it.
  #
  # The second statement is a data repair rather than a spelling change, and it
  # is the reason this migration exists at all. Because the old form's option
  # values were Rails names, a user whose column held the IANA default matched
  # no option; the browser fell back to the first entry in the list, which is
  # International Date Line West, and saving the profile stored UTC-12. Nobody
  # chooses UTC-12 — its only land is uninhabited — so a row holding it is a
  # record of that bug and not of anyone's intent. The one account carrying it
  # belongs to a user in Massachusetts, hence Eastern.
  DEFAULT_ZONE = "America/New_York".freeze
  BUG_SENTINEL_ZONE = "Etc/GMT+12".freeze

  def up
    ActiveSupport::TimeZone.all.each do |zone|
      next if zone.name == zone.tzinfo.name

      update_zone from: zone.name, to: zone.tzinfo.name
    end

    update_zone from: BUG_SENTINEL_ZONE, to: DEFAULT_ZONE
  end

  # Deliberately one-way. Reversing the spelling would rewrite the rows that
  # were correct all along, and no reversal can distinguish the account moved
  # off UTC-12 here from one that had always been set that way.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def update_zone(from:, to:)
    execute ActiveRecord::Base.sanitize_sql_array(
      [ "UPDATE users SET tz = ? WHERE tz = ?", to, from ]
    )
  end
end
