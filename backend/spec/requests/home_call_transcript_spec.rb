# frozen_string_literal: true

require "rails_helper"

# The homepage prints a transcript of a reminder call — the single thing a
# visitor most wants to see and could not, until it was added, find anywhere on
# the site. It is quoted as if it were a recording, which is only honest for as
# long as it matches the script the app actually speaks.
#
# Nothing else holds those two together. The copy lives in an ERB template and
# the script lives in config/locales/voice.en.yml; reword the announcement, ship
# it, and the homepage goes on quoting a call that no longer happens. That is a
# worse failure than a stale paragraph, because a caregiver reads this to decide
# whether an automated voice will frighten their mother.
#
# So these compare the page against I18n and against the constants, not against
# a second copy of the wording. Rewrite the script freely — this fails until the
# homepage is rewritten with it.
RSpec.describe "The call transcript on the homepage", type: :request do
  before { get "/" }

  def doc = @doc ||= Nokogiri::HTML(response.body)
  def section = doc.at_css("section.transcript")

  # Curly quotes on the page, straight quotes in nothing this compares against;
  # newlines and ERB indentation between every word. Compare on the words.
  #
  # The curly quotes are written as escapes on purpose. They were literals, and
  # a literal pair of curly quotes inside a character class is indistinguishable
  # at a glance from a pair of ASCII ones -- which is what they had silently
  # become, making the whole gsub a no-op that replaced " with ".
  CURLY_QUOTES = /[\u201C\u201D\u2018\u2019]/

  def normalised(string)
    string.gsub(CURLY_QUOTES, '"').gsub(/\s+/, " ").strip
  end

  # Guarded here rather than relying on the "is on the page" example to fail
  # first: RSpec orders examples randomly, so without this the other four fail
  # with NoMethodError on nil and say nothing about what is actually wrong.
  def description = doc.at_css("meta[name='description']")&.[]("content").to_s

  def transcript_text
    @transcript_text ||= begin
      raise "the call transcript section is gone from the homepage" if section.nil?

      normalised(section.text)
    end
  end

  it "is on the page" do
    expect(section).to be_present, "the call transcript section is gone from the homepage"
  end

  # The helper's whole job, asserted directly. It was a no-op for its first
  # revision and nothing noticed, because the strings it compares happen not to
  # contain quotes -- so the one line that would break if it regressed is here.
  it "normalises the quotes the page is actually written with" do
    expect(normalised("\u201CHello\u201D")).to eq('"Hello"')
  end

  # Played first on every reminder call, and the only thing an answering machine
  # can record. A transcript that opened on the announcement would be showing a
  # call that never happens in that order.
  it "opens on the line the call actually opens on" do
    expect(transcript_text).to include(normalised(I18n.t("voice.screening", locale: :en)))
  end

  # The name and the task are the page's own example; the minutes are not, and
  # a transcript offering to ring back in ten while the app rings back in five
  # is the kind of small lie that costs a signup at the moment it is noticed.
  it "quotes the announcement the app speaks, including the snooze interval" do
    spoken = I18n.t(
      "voice.announcement",
      name: "Margaret",
      task: "Take your morning medication",
      minutes: Occurrence::SNOOZE_DEFAULT_MINUTES,
      locale: :en
    )

    expect(transcript_text).to include(normalised(spoken))
  end

  # The transcript shows a keypress, so the page must not also be claiming the
  # call observes anything more than one. Same standard as the rest of the page.
  it "does not turn the keypress into proof the medication was swallowed" do
    expect(transcript_text).not_to match(/confirms? (that )?(she|they|it) (has |have )?(taken|swallowed)/i)
  end

  # A telephone reminder takes two presses -- one to get past the screening
  # line, one to answer the reminder -- and the transcript prints both. Copy
  # elsewhere on the page said "they press one key", which the page then
  # disproved a few inches further down. Whatever it says, it must not say one.
  it "does not claim a telephone reminder takes a single keypress" do
    # Body prose plus the meta description, which is where the claim last
    # survived a rewrite of the visible copy -- and is the sentence Google
    # prints, so the most-read version of it. Deliberately not doc.text: that
    # sweeps in the inlined <style> and the JSON-LD, and a CSS comment is not
    # a promise to anybody.
    prose = normalised([ doc.at_css("body").text, description ].join(" "))

    expect(prose).not_to match(/press(es)? (only )?one key\b|one key to press\b/i)
  end

  # Not part of the transcript, but the paragraph directly under it, and true
  # for the same reason: these are the numbers the retry logic runs on.
  describe "the paragraph about a call that goes unanswered" do
    def page_text = @page_text ||= normalised(doc.text)

    WORDS = { 1 => "one", 2 => "two", 3 => "three", 4 => "four", 5 => "five" }.freeze

    it "states the number of attempts the code actually makes" do
      expect(TelnyxCall::MAX_ATTEMPTS).to be <= 5,
        "MAX_ATTEMPTS outgrew the words this spec knows — extend WORDS and the copy"
      expect(page_text).to match(/up to #{WORDS.fetch(TelnyxCall::MAX_ATTEMPTS)} times/i)
    end

    it "states the gap between attempts that the code actually waits" do
      minutes = (TelnyxCall::RETRY_AFTER / 60).to_i
      expect(minutes).to be <= 5,
        "RETRY_AFTER outgrew the words this spec knows — extend WORDS and the copy"
      expect(page_text).to match(/#{WORDS.fetch(minutes)} minutes apart/i)
    end

    # notify_unanswered returns early unless the reminder is critical?, and the
    # dashboard offers that as "being late matters". Promising the alert without
    # the condition would promise every caregiver an email on every silent
    # hydration call.
    it "ties the unanswered alert to the setting that gates it" do
      expect(page_text).to match(/being late matters/i)
    end

    # The page said the caregiver is emailed "on every attempt that goes
    # unanswered". They are not: Notification has a unique index on
    # (user_id, notification_type, occurrence_id), create_notification returns
    # nil on the second attempt, and the mail is skipped with it -- which
    # critical_reminder_alert_spec has always asserted as "tells each caregiver
    # once, however many attempts go unanswered".
    #
    # Promising three emails and sending one is the failure mode this product
    # can least afford: somebody waits for a second alert that is never coming.
    it "does not promise an email for every unanswered attempt" do
      expect(page_text).not_to match(/(every|each) (unanswered )?attempt/i)
      expect(page_text).to match(/once, not once per attempt/i)
    end
  end
end
