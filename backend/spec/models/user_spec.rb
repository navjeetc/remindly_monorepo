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

  describe "#assign_self_role" do
    it "lets a brand-new (role-less, name-less) user pick senior or caregiver" do
      user = User.create!(email: "new@example.com", tz: "America/New_York") # role nil, no name

      expect(user.assign_self_role("caregiver")).to be_truthy
      expect(user.reload.role).to eq("caregiver")

      expect(user.assign_self_role("senior")).to be_truthy
      expect(user.reload.role).to eq("senior")
    end

    it "refuses to self-grant admin or any non-role value" do
      user = User.create!(email: "new@example.com", tz: "America/New_York")

      expect(user.assign_self_role("admin")).to be(false)
      expect(user.assign_self_role("bogus")).to be(false)
      expect(user.assign_self_role(nil)).to be(false)
      expect(user.reload.role).to be_nil
    end

    it "will not change an existing admin's role" do
      admin = create(:user, :admin, name: "Boss")

      expect(admin.assign_self_role("caregiver")).to be(false)
      expect(admin.reload.role).to eq("admin")
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
