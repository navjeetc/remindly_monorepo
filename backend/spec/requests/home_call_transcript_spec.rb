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

  # Curly quotes on the page, straight quotes nowhere; newlines and ERB
  # indentation between every word. Compare on the words.
  def normalised(string)
    string.gsub(/[""]/, '"').gsub(/\s+/, " ").strip
  end

  def transcript_text = @transcript_text ||= normalised(section.text)

  it "is on the page" do
    expect(section).to be_present, "the call transcript section is gone from the homepage"
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
  end
end
