# frozen_string_literal: true

require "rails_helper"

# Reminder phone calls have been on in production since ENABLE_PHONE_CALL_REMINDERS
# was turned on, and until this copy landed the public site did not mention them
# once — the only page that admitted Remindly telephones anybody was the privacy
# policy, warning about it. Worse, the pages that sell the product told the
# reader the opposite: the landing page's search description promised "no phone
# to check", which reads to somebody with no tablet in the house as "not for you".
#
# These pin the claims a visitor and a crawler can see. They are about the copy
# existing and staying accurate, not about wording — anything here can be
# rewritten, but it should not quietly disappear, and it should not start
# promising more than the feature does.
RSpec.describe "What the public pages say about reminder phone calls", type: :request do
  def text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")
  def description = Nokogiri::HTML(response.body).at_css("meta[name='description']")&.[]("content").to_s

  shared_examples "a page that mentions reminder calls" do
    it "says Remindly can telephone the care receiver" do
      expect(text).to match(/telephone/i)
    end

    it "says the calls are agreed to first" do
      expect(text).to match(/press 1|never ask for personal details/i)
    end

    it "says how to stop them" do
      expect(text).to match(/press 9|9.{0,40}stop/i)
    end

    # The Spanish script is live but has not been read by a native speaker, so
    # the site should not be advertising languages we have not had checked.
    it "does not advertise a language the script has not been reviewed in" do
      expect(text).not_to match(/spanish|español|mandarin|cantonese/i)
    end

    # Pressing 1 records an acknowledgement, exactly as the Done button does. It
    # is not evidence that anybody swallowed anything, and medication is the
    # wrong subject to get loose about.
    it "does not claim the call proves the medication was taken" do
      expect(text).not_to match(/confirms? (that )?(they|the medication|it) (was )?(taken|swallowed)/i)
    end

    # Every one of these was in the first draft of this copy and every one was
    # false. They are pinned individually because each overstates a different
    # thing, and the first three concern how much control the person being
    # telephoned actually has.

    # DashboardController#verify_phone: "An opt-out is deliberately not a block
    # here." A caregiver with manage permission may place a consent call after
    # a 9, capped per day. Pressing 9 stops the reminders; it does not end
    # contact for good, and saying so to an elderly person would be a promise
    # the product does not keep.
    it "does not promise the opt-out is permanent" do
      expect(text).not_to match(/for good|never (call|telephone|ring)|permanently/i)
    end

    # User::CALLING_HOURS = (8...21). VoiceReminderJob suppresses anything
    # outside it, so a dose due at 6am or 10pm is never telephoned.
    it "states the hours calls are made within" do
      expect(text).to match(/8\s*am.{0,12}9\s*pm/i)
    end

    # TelnyxCall::MAX_ATTEMPTS is a ceiling, not a promise: the calling-hours
    # window or MAX_CALLS_PER_DAY can end the attempts early.
    it "describes the retries as a limit rather than a guarantee" do
      expect(text).to match(/up to three/i)
      expect(text).not_to match(/three times in all/i)
    end

    # notify_unanswered_if_critical returns unless the reminder is critical, and
    # the hour-later missed notice obeys each caregiver's category preferences,
    # which are off by default for hydration and routine.
    it "ties the unanswered alert to the time-critical flag" do
      expect(text).to match(/being late matters/i)
    end
  end

  describe "GET /how_to" do
    before { get "/how_to" }

    include_examples "a page that mentions reminder calls"

    it "tells the reader an ordinary phone is enough" do
      expect(text).to match(/landline or mobile|ordinary landline/i)
    end

    it "says a caregiver is told when a call goes unanswered" do
      expect(text).to match(/unanswered/i)
    end
  end

  describe "GET /reminder-app-for-elderly-parents" do
    before { get "/reminder-app-for-elderly-parents" }

    include_examples "a page that mentions reminder calls"

    # This is the page that competes for "reminder app for elderly parents", and
    # the description is the sentence a search result prints.
    it "offers the phone in the sentence search results show" do
      expect(description).to match(/telephone call/i)
    end

    it "no longer tells a reader with no tablet they need a device" do
      expect(description).not_to match(/no phone to check/i)
    end

    it "meets the scam objection rather than ignoring it" do
      expect(text).to match(/never ask (you )?for personal details/i)
    end
  end
end
