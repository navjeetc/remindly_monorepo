# frozen_string_literal: true

# Six digits somebody can read down a telephone.
#
# A capability URL nobody can get onto a device is not finished. Typing 43
# characters of urlsafe_base64 on a tablet keyboard is not a plan for somebody
# whose eyesight is part of why you are setting this up, a QR code needs a
# camera the kitchen desktop does not have, and emailing the link is ruled out —
# it means sending mail to an address nobody has verified, from the domain every
# magic link leaves, which is how a project ends up unable to log anyone in.
#
# So the caregiver reads out six digits and the care receiver types them at
# /start. It is the one channel this audience is comfortable with: every other
# remote option asks an older person to find a message in an inbox and trust a
# link inside it, which is the exact interaction they are told never to trust.
#
# Six digits are guessable where 32 bytes are not, so the code carries the
# burden the URL does not: ten minutes, single use, and rate limiting at the
# endpoint. The link it unlocks does not expire; the code does.
class AddStartCodeToReminderLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :reminder_links, :start_code, :string
    add_column :reminder_links, :start_code_expires_at, :datetime

    # Partial, because a used or expired code is cleared to NULL and any number
    # of links may have none — while no two may offer the same digits at once.
    add_index :reminder_links, :start_code, unique: true, where: "start_code IS NOT NULL"
  end
end
