# frozen_string_literal: true

# The contact card for the number Remindly calls from.
#
# A plain model with no table, like Post: there is exactly one of these and it
# is made of a credential, so there is nothing to persist. It exists because
# "save our number as a contact" is the step that decides whether a reminder
# call is heard at all -- a saved number shows a name instead of an unknown
# caller, and it clears iOS Silence Unknown Callers, which otherwise sends the
# call to voicemail without ringing. A voicemail cannot press 1, so a screened
# consent call is not a delayed setup, it is a setup that never completes.
#
# The card is offered as a file rather than only as digits to read out because
# the person who must save it is usually not the person reading the screen: the
# caregiver is elsewhere, and a .vcf can be sent by message or mail and opened
# with one tap at the other end.
class CallerIdCard
  # RFC 6350 wants CRLF between lines, and the phones that matter are stricter
  # about it than the spec is -- a card with bare newlines imports with empty
  # fields on some Android builds rather than failing outright, which is the
  # worse outcome: the caregiver believes the number is saved.
  LINE_ENDING = "\r\n"

  # 3.0 rather than 4.0. Both are current, and 3.0 is what iOS and Android have
  # imported without argument for a decade; 4.0 buys nothing a one-number card
  # needs.
  VERSION = "3.0"

  NAME = "Remindly"

  def initialize(number)
    @number = number
  end

  def to_vcf
    [
      "BEGIN:VCARD",
      "VERSION:#{VERSION}",
      "N:;#{NAME};;;",
      "FN:#{NAME}",
      "ORG:#{NAME}",
      "TEL;TYPE=VOICE:#{@number}",
      "NOTE:#{note}",
      "END:VCARD",
      ""
    ].join(LINE_ENDING)
  end

  def filename = "#{NAME}.vcf"

  private

    # Whoever opens this card may never have heard of Remindly -- the caregiver
    # arranged it, and the card arrives on somebody else's phone. It says who is
    # calling and what the call asks for, so an unexplained file is not the first
    # thing they learn about us.
    #
    # Commas and semicolons carry meaning inside a vCard value and have to be
    # escaped, so the note is written without them rather than escaped after the
    # fact: one fewer thing to get wrong in a file no test can open on a handset.
    def note
      "Reminder calls come from this number. Answer and press 1 to confirm."
    end
end
