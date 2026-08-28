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

    it "refuses a language Telnyx cannot speak" do
      sign_in(caregiver)

      expect {
        patch "/dashboard/senior/#{senior.id}/spoken_language",
          params: { user: { spoken_language: "yue-HK" } }
      }.not_to change { senior.reload.spoken_language }
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

  describe "the script" do
    # The trap this guards: i18n.fallbacks is on in production, so a missing
    # Spanish key falls back to English *text* while the payload still says
    # es-US — a Spanish voice reading English words to somebody who may not
    # speak it. The words and the accent have to be chosen together.
    it "has every English key translated, in every language offered" do
      english = I18n.t("voice", locale: :en)

      User::SPOKEN_LANGUAGES.each_value do |meta|
        translated = I18n.t("voice", locale: meta[:locale])

        expect(flatten_keys(translated)).to match_array(flatten_keys(english)),
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
