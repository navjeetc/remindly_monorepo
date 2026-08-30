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
  # Parsed once per example rather than once per call: several examples read
  # `text` two or three times, and each read was reparsing the whole document.
  # Safe because every group here issues its single request in a before hook and
  # no example makes a second one — if one ever does, it has to reset these.
  def doc = @doc ||= Nokogiri::HTML(response.body)
  def text = @text ||= doc.text.gsub(/\s+/, " ")
  def description = doc.at_css("meta[name='description']")&.[]("content").to_s

  shared_examples "a page that mentions reminder calls" do
    # Not a bare /telephone/: the landing page has said "talking someone through
    # a settings screen over the telephone" since long before any of this, so
    # the bare match was satisfied by copy arguing the opposite point, and every
    # sentence about Remindly placing calls could have gone with the spec still
    # green. The subject has to be in the match.
    it "says Remindly can telephone the care receiver" do
      expect(text).to match(/Remindly can telephone/i)
    end

    # Both of these matched their own button list before review pointed it out.
    # "press 1" appears in the instructions for a normal reminder call, so the
    # entire consent explanation could have been deleted with the spec still
    # green; "press 9" likewise. What each claim needs pinned is the sentence
    # that makes the promise, not the digit.
    it "says the calls are agreed to first" do
      expect(text).to match(/never ask (you )?for personal details/i)
      # No alternation: the second branch used to be "starts the reminders only
      # if", which matched without naming the keypress at all — so the copy
      # could have stopped saying what a person must do to start the calls and
      # this would still have passed. Both pages phrase it as "only if ...
      # press(es) 1", so one pattern covers them and every match now contains
      # the mechanism.
      expect(text).to match(/only if (the person|they) press(es)? 1/i)
    end

    it "says that 9 is what stops them" do
      expect(text).to match(/9[^.]{0,20}stops? the reminder calls/i)
    end

    # The Spanish script is live but has not been read by a native speaker, so
    # the site should not be advertising languages we have not had checked.
    it "does not advertise a language the script has not been reviewed in" do
      expect(text).not_to match(/spanish|español|mandarin|cantonese/i)
    end

    # The other half of the same problem, and the direction it actually failed
    # in. ENABLE_TRANSLATED_CALLS is true in production, so a caregiver can
    # choose Spanish today and "calls are spoken in English" was simply untrue.
    # These pages say nothing about language now: claiming English-only is
    # false, and naming Spanish would recruit families to a script no native
    # speaker has read. Silence is the only accurate option until it is
    # reviewed, at which point this guard should be replaced by one asserting
    # the languages are named.
    it "does not claim the calls are English-only" do
      expect(text).not_to match(/spoken in English|English only|only in English|in English\./i)
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

  # The root page is the strongest surface of the three and was the last to say
  # any of this. Its heading actively excluded the readers the calls were built
  # for: "Works with the tablet or computer they already use" answers "what
  # device do I need" with two, when the true answer is that a telephone will do.
  describe "GET / (the homepage)" do
    before { get "/" }

    it "does not tell a reader with no tablet that they need a device" do
      heading = doc.at_css("section.setup h2")

      expect(heading).to be_present
      expect(heading.text).to match(/telephone/i)
    end

    it "offers the telephone in the sentence search results show" do
      expect(description).to match(/telephone call/i)
    end

    it "states the hours and the opt-out rather than only the good part" do
      expect(text).to match(/8\s*am.{0,12}9\s*pm/i)
      expect(text).to match(/9[^.]{0,20}stops? the reminder calls/i)
    end

    it "does not promise the opt-out is permanent" do
      expect(text).not_to match(/for good|never (call|telephone|ring)|permanently/i)
    end

    # Four sentences and a link. The argument for the calls lives on the pages
    # written to make it; this one only has to stop disqualifying people.
    it "points at the page that explains the calls" do
      expect(doc.css("section.setup a").map { |a| a["href"] }).to include("/how_to")
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
