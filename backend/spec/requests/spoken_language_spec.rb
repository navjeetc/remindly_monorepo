# frozen_string_literal: true

require "rails_helper"

# Remindly telephones people who may not read a screen, and some of them do not
# speak English either. The setting is on the senior because it is their ear it
# serves; it is set by the caregiver because the senior is often the one who
# never signs in, which is the same fact that makes the calls worth having.
RSpec.describe "The language calls are spoken in", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # Both flags default off. These specs are about what happens once a reviewer
  # has signed off a script and calls are switched on; the specs that it stays
  # shut until then are in "before a script has been reviewed" below.
  #
  # and_call_original first, or the stub swallows every other flag lookup and
  # the senior page dies on external_scheduling.
  before do
    allow(FeatureFlag).to receive(:enabled?).and_call_original
    allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
    allow(FeatureFlag).to receive(:enabled?).with(:translated_calls).and_return(true)
  end

  describe "the setting" do
    it "starts in English, so nobody's calls change under them" do
      expect(senior.spoken_language).to eq("en-US")
      expect(senior.spoken_locale).to eq(:en)
    end

    it "is set by the caregiver from the senior's page" do
      sign_in(caregiver)

      patch "/dashboard/senior/#{senior.id}/spoken_language",
        params: { user: { spoken_language: "es-US" } }

      expect(senior.reload.spoken_language).to eq("es-US")
      expect(senior.spoken_locale).to eq(:es)
    end

    # Cantonese is the real case: it was asked for and is absent from Telnyx's
    # speak enum entirely. Asserting the status as well as the stored value,
    # because "the database did not change" is also true of a 500 — and a spec
    # that passes when the endpoint explodes is worse than no spec, since it
    # reads like a guarantee.
    it "refuses a language Telnyx cannot speak" do
      sign_in(caregiver)

      expect {
        patch "/dashboard/senior/#{senior.id}/spoken_language",
          params: { user: { spoken_language: "yue-HK" } }
      }.not_to change { senior.reload.spoken_language }

      expect(response).to have_http_status(:forbidden)
    end

    it "is not settable by a caregiver with only view permission" do
      viewer = create(:user, :caregiver, name: "Sam")
      CaregiverLink.create!(senior: senior, caregiver: viewer, permission: :view)
      sign_in(viewer)

      patch "/dashboard/senior/#{senior.id}/spoken_language",
        params: { user: { spoken_language: "es-US" } }

      expect(response).to have_http_status(:forbidden)
      expect(senior.reload.spoken_language).to eq("en-US")
    end
  end

  # Remindly translates its own words, not the caregiver's. The title reaches
  # the voice exactly as typed, so without saying so a senior set to Spanish
  # hears "Take meds" in the middle of a Spanish sentence — and the caregiver
  # who set the language has no way to know that from the screen.
  describe "warning that titles are spoken verbatim" do
    def page_text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

    it "says nothing when the calls are in English" do
      sign_in(caregiver)
      get "/dashboard/senior/#{senior.id}/reminder/new"

      expect(page_text).not_to include("read out exactly as you type it")
    end

    it "warns on the reminder form once the calls are not in English" do
      senior.update!(spoken_language: "es-US")
      sign_in(caregiver)
      get "/dashboard/senior/#{senior.id}/reminder/new"

      expect(page_text).to include("Mom's calls are spoken in Español")
      expect(page_text).to include("read out exactly as you type it")
    end

    it "warns beside the language control itself, where the choice is made" do
      senior.update!(spoken_language: "es-US", phone: "+15551234567")
      sign_in(caregiver)
      get "/dashboard/senior/#{senior.id}"

      expect(page_text).to include("Write reminder titles in Español too")
    end
  end

  # Production runs with phone calls on, so a language whose script nobody has
  # read would otherwise be selectable for real calls the day it merged. The
  # first Spanish draft told a senior named Mom that the call was being made on
  # Mom's own behalf, which is what that costs.
  describe "before a script has been reviewed" do
    before do
      allow(FeatureFlag).to receive(:enabled?).with(:translated_calls).and_return(false)
    end

    it "offers English only" do
      expect(User.selectable_spoken_languages.keys).to eq([ "en-US" ])
    end

    # The guarantee that matters. Hiding the control only removes the easy path;
    # the flag is not a gate until the endpoint enforces it, and this is exactly
    # the mistake the phone_call_reminders guard existed to prevent, repeated one
    # layer down.
    it "refuses a crafted PATCH setting a language nobody has reviewed" do
      sign_in(caregiver)

      patch "/dashboard/senior/#{senior.id}/spoken_language",
        params: { user: { spoken_language: "es-US" } }

      expect(response).to have_http_status(:forbidden)
      expect(senior.reload.spoken_language).to eq("en-US")
    end

    it "still accepts English, which needs no review" do
      senior.update!(spoken_language: "es-US")
      sign_in(caregiver)

      patch "/dashboard/senior/#{senior.id}/spoken_language",
        params: { user: { spoken_language: "en-US" } }

      expect(senior.reload.spoken_language).to eq("en-US")
    end

    it "hides the control rather than showing a list of one" do
      senior.update!(phone: "+15551234567")
      sign_in(caregiver)
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).not_to include("user_spoken_language")
    end

    # Gating the choice, not playback. Taking a language away from somebody
    # already relying on it is worse than the risk the flag was covering.
    it "keeps speaking a language already chosen" do
      senior.update!(spoken_language: "es-US")

      expect(senior.reload.spoken_locale).to eq(:es)
    end
  end

  describe "when phone calls are switched off entirely" do
    before do
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(false)
    end

    # The panel is hidden, so the only way to this route is a hand-made request.
    it "refuses to change what a telephone says" do
      sign_in(caregiver)

      patch "/dashboard/senior/#{senior.id}/spoken_language",
        params: { user: { spoken_language: "es-US" } }

      expect(response).to have_http_status(:forbidden)
      expect(senior.reload.spoken_language).to eq("en-US")
    end
  end

  describe "the script" do
    # The trap this guards: i18n.fallbacks is on in production, so a missing
    # Spanish key falls back to English *text* while the payload still says
    # es-US — a Spanish voice reading English words to somebody who may not
    # speak it. The words and the accent have to be chosen together.
    # Read out of the backend rather than through I18n.t. Production enables
    # i18n.fallbacks, and a lookup for a missing Spanish key returns the English
    # string rather than nothing — so a parity check built on I18n.t would pass
    # while the exact hole it exists to find was open. It passes today only
    # because the test environment happens not to enable fallbacks, which is not
    # a fact this spec should depend on.
    def script_keys(locale)
      I18n.backend.send(:init_translations) unless I18n.backend.initialized?
      flatten_keys(I18n.backend.send(:translations).fetch(locale).fetch(:voice))
    end

    it "has every English key translated, in every language offered" do
      english = script_keys(:en)

      User::SPOKEN_LANGUAGES.each_value do |meta|
        expect(script_keys(meta[:locale])).to match_array(english),
          "#{meta[:label]} is missing keys the English script has"
      end
    end

    it "speaks Spanish to a senior set to Spanish" do
      senior.update!(spoken_language: "es-US")
      reminder = Reminder.create!(user: senior, title: "Tomar las pastillas", rrule: "FREQ=DAILY", tz: senior.tz)

      spoken = I18n.t("voice.announcement",
        name: senior.display_name, task: reminder.title,
        minutes: Occurrence::SNOOZE_DEFAULT_MINUTES, locale: senior.spoken_locale)

      expect(spoken).to include("Pulse 1")
      expect(spoken).not_to include("Press 1")
    end

    it "keeps the keypad digits out of translation" do
      User::SPOKEN_LANGUAGES.each_value do |meta|
        script = I18n.t("voice.announcement", name: "X", task: "Y", minutes: 10, locale: meta[:locale])

        expect(script).to include("1", "2", "9")
      end
    end
  end

  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flatten_keys(value, path) : [ path ]
    end
  end
end
