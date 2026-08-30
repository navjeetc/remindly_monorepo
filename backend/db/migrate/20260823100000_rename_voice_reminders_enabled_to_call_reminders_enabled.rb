# frozen_string_literal: true

# "Voice reminders" already means something else in this app: the spoken
# announcements on /voice_reminders, which a senior hears from a screen they are
# signed in to. Telephone calls are a different feature reaching a different
# person by a different route, and one boolean named for both invites exactly the
# confusion the two features cannot afford.
#
# The parent design document has called this call_reminders_enabled throughout.
# Renamed now because the column is live in production with no row set true, so
# it carries no data and nothing depends on its value yet — the cheapest this
# will ever be.
class RenameVoiceRemindersEnabledToCallRemindersEnabled < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :voice_reminders_enabled, :call_reminders_enabled
  end
end
