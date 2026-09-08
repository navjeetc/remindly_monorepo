# frozen_string_literal: true

require "rails_helper"

# What the public pages promise about the price. These are not descriptions, they
# are commitments: somebody reads them and then wires their mother's morning dose
# to this, and rewriting the sentence afterwards does not take it back from the
# person who already acted on it. So the promises are pinned, and the one that
# was dropped is pinned as dropped.
RSpec.describe "The free promise on the public pages", type: :request do
  PAGES = [ "/", "/reminder-app-for-elderly-parents" ].freeze

  def note
    Nokogiri::HTML(response.body).at_css("p.free-note")&.text.to_s.gsub(/\s+/, " ")
  end

  PAGES.each do |path|
    describe "GET #{path}" do
      before { get path }

      # Cheap to keep for good, and the reason somebody trusts a free product
      # with a parent's medication.
      it "keeps the promises that cost nothing to honour" do
        expect(note).to match(/no card/i)
        expect(note).to match(/no ads/i)
        expect(note).to match(/no sales calls/i)
      end

      # Deliberately removed. A cap on reminders is the most ordinary way this
      # could one day be charged for, and the clause persuaded nobody -- the
      # page's own note called it a worry nobody arrives with. If it comes back,
      # it should come back as a decision rather than by accident.
      it "does not promise an unlimited number of reminders" do
        expect(note).not_to match(/no limit|unlimited/i)
      end

      # The load-bearing one, and still pinned word for word.
      #
      # 2026-09-08: the surrounding note now reads "Free while in beta", which
      # is the business decision this comment used to be waiting for. The
      # sentence itself did not soften and must not: "no trial that quietly
      # ends" was never a promise that a price could never come, only that one
      # would never arrive silently — and the note now says out loud that
      # anyone using Remindly hears first. Breaking that later costs more than
      # softening it early would have.
      it "still promises the free version will not quietly end" do
        expect(note).to match(/no trial that quietly ends/i)
      end
    end
  end
end
