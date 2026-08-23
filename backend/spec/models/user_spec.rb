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

    # Asserts on the value, not the label: ActiveSupport's label text tracks
    # zoneinfo and has changed format before, and none of that is what this
    # guards. The identifier is the half the column has to agree with.
    it "offers options whose values are the identifiers it stores" do
      values = User::TIMEZONE_OPTIONS.map { |_label, identifier| identifier }

      expect(values).to include("America/New_York")
      expect(values).not_to include("Eastern Time (US & Canada)")
    end

    it "labels each option, so the list is readable" do
      labels = User::TIMEZONE_OPTIONS.to_h.invert

      expect(labels.fetch("America/New_York")).to include("Eastern Time (US & Canada)")
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

  # Outbound reminder calls are legally restricted to 8am-9pm where the person
  # answering actually is, which makes tz the thing this rule stands on.
  describe "#within_calling_hours?" do
    def at(hour, zone: "America/New_York", minute: 0)
      ActiveSupport::TimeZone[zone].local(2026, 6, 15, hour, minute)
    end

    let(:senior) { build(:user, tz: "America/New_York") }

    it "allows a call at 8am, the first legal minute" do
      expect(senior.within_calling_hours?(at: at(8))).to be true
    end

    it "allows a call at 20:59, the last legal minute" do
      expect(senior.within_calling_hours?(at: at(20, minute: 59))).to be true
    end

    it "refuses a call at 21:00, when the window closes" do
      expect(senior.within_calling_hours?(at: at(21))).to be false
    end

    it "refuses a call at 7:59, before the window opens" do
      expect(senior.within_calling_hours?(at: at(7, minute: 59))).to be false
    end

    it "refuses the small hours" do
      expect(senior.within_calling_hours?(at: at(3))).to be false
    end

    it "judges by the senior's own clock, not the server's" do
      pacific = build(:user, tz: "America/Los_Angeles")

      # 06:30 in Los Angeles is 09:30 in New York: legal for one, not the other.
      moment = ActiveSupport::TimeZone["America/Los_Angeles"].local(2026, 6, 15, 6, 30)

      expect(pacific.within_calling_hours?(at: moment)).to be false
      expect(senior.within_calling_hours?(at: moment)).to be true
    end

    it "refuses when the zone cannot be resolved, rather than assuming daytime" do
      senior.tz = "Neverwhere/Nowhere"

      expect(senior.within_calling_hours?(at: at(12))).to be false
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
