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

  describe "#tz" do
    it "stores a Rails zone name as its IANA identifier" do
      user = create(:user, :caregiver, name: "Kid", tz: "Eastern Time (US & Canada)")

      expect(user.reload.tz).to eq("America/New_York")
    end

    it "leaves an identifier alone" do
      expect(User.new(tz: "Asia/Kolkata").tz).to eq("Asia/Kolkata")
    end

    it "refuses a zone that resolves to nothing, rather than silently blanking it" do
      user = build(:user, :caregiver, name: "Kid", tz: "Middle Earth")

      expect(user).not_to be_valid
      expect(user.errors[:tz]).to include("is not a valid timezone")
    end

    it "offers options whose values are the identifiers it stores" do
      expect(User::TIMEZONE_OPTIONS).to include([ "(GMT-05:00) Eastern Time (US & Canada)", "America/New_York" ])
    end

    it "keeps a stored zone selectable even when Rails' curated list omits it" do
      user = build(:user, tz: "America/Detroit") # resolves, but not one of Rails' names

      expect(user.timezone_options).to include([ "America/Detroit", "America/Detroit" ])
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

    # The guard must read the database, not a possibly-stale in-memory role — so a
    # concurrent promotion to admin can't be overwritten.
    it "refuses based on the persisted role even if the loaded object is stale" do
      admin = create(:user, :admin, name: "Boss")
      stale = User.find(admin.id)
      stale.role = "caregiver" # pretend this instance predates the promotion

      expect(stale.assign_self_role("senior")).to be(false)
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
