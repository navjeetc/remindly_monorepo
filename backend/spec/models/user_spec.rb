require "rails_helper"

RSpec.describe User do
  describe "#notify_reminder_categories" do
    it "defaults a new user to medication only" do
      expect(User.new.notify_reminder_categories).to eq([ "medication" ])
    end

    it "keeps only real reminder categories, dropping junk and blanks" do
      user = create(:user, :caregiver, name: "Kid")
      user.update!(notify_reminder_categories: [ "medication", "hydration", "", "bogus" ])

      expect(user.reload.notify_reminder_categories).to contain_exactly("medication", "hydration")
    end

    it "de-duplicates" do
      user = create(:user, :caregiver, name: "Kid")
      user.update!(notify_reminder_categories: [ "routine", "routine" ])

      expect(user.reload.notify_reminder_categories).to eq([ "routine" ])
    end

    it "coerces a nil selection to an empty set" do
      user = create(:user, :caregiver, name: "Kid")
      user.update!(notify_reminder_categories: nil)

      expect(user.reload.notify_reminder_categories).to eq([])
    end
  end

  describe "#notified_for?" do
    it "is true only for chosen categories" do
      user = create(:user, :caregiver, name: "Kid", notify_reminder_categories: %w[medication])

      expect(user.notified_for?("medication")).to be(true)
      expect(user.notified_for?(:medication)).to be(true)
      expect(user.notified_for?("hydration")).to be(false)
    end
  end
end
