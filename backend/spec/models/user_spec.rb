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

  # Consent is to a number, not to a person. A caregiver who edits this field
  # would otherwise inherit agreement given by somebody else — the failure the
  # whole consent design exists to prevent, reached through a text field.
  describe "consent when the phone number changes" do
    let(:senior) { create(:user, :senior, name: "Mom", phone: "+15551110000") }

    before do
      senior.update!(phone_verified_at: Time.current, call_consent_at: Time.current,
                     call_reminders_enabled: true)
    end

    it "forgets that the old number was verified" do
      expect { senior.update!(phone: "+15552220000") }
        .to change { senior.reload.phone_verified_at }.to(nil)
    end

    it "forgets the consent given for the old number" do
      expect { senior.update!(phone: "+15552220000") }
        .to change { senior.reload.call_consent_at }.to(nil)
    end

    it "stops calls until the new number agrees for itself" do
      senior.update!(phone: "+15552220000")

      expect(senior.reload.call_reminders_enabled).to be false
    end

    it "leaves consent alone when something else is saved" do
      senior.update!(name: "Margaret")

      expect(senior.reload.call_consent_at).to be_present
      expect(senior.call_reminders_enabled).to be true
    end

    it "forgets consent when the number is removed entirely" do
      senior.update!(phone: nil)

      expect(senior.reload.call_consent_at).to be_nil
      expect(senior.call_reminders_enabled).to be false
    end

    # The callback skips a blank previous number so it cannot wipe consent being
    # granted in the same save. That skip must not extend to a record already
    # holding consent facts: consent! writes them through update_all, so a record
    # can carry an agreement with no number on it, and the *first* number saved
    # afterwards would otherwise inherit an agreement given for another handset.
    it "does not let a first number inherit consent left over from another one" do
      orphan = create(:user, :senior, name: "Nan", phone: nil)
      orphan.update_columns(phone_verified_at: Time.current, call_consent_at: Time.current,
                            call_reminders_enabled: true)

      orphan.update!(phone: "+15553330000")

      expect(orphan.reload.call_consent_at).to be_nil
      expect(orphan.phone_verified_at).to be_nil
      expect(orphan.call_reminders_enabled).to be false
      expect(orphan.callable_by_phone?).to be false
    end

    # The other half of that rule, and the reason the skip exists at all.
    it "still allows a number and its consent to be written in one save" do
      fresh = create(:user, :senior, name: "New", phone: "+15554440000",
                                     phone_verified_at: Time.current,
                                     call_consent_at: Time.current,
                                     call_reminders_enabled: true)

      expect(fresh.reload.call_consent_at).to be_present
      expect(fresh.call_reminders_enabled).to be true
    end

    # There is nothing to forget when there was no previous number. Clearing here
    # would defeat any single save that sets a number and its consent together,
    # silently — which reads as caution and is simply a bug.
    it "does not wipe consent granted in the same save as the first number" do
      fresh = create(:user, :senior, name: "Dad", phone: "+15557770000",
                                     phone_verified_at: Time.current,
                                     call_consent_at: Time.current,
                                     call_reminders_enabled: true)

      expect(fresh.reload.call_reminders_enabled).to be true
      expect(fresh.call_consent_at).to be_present
    end

    it "does not wipe consent when a number is added to a user who had none" do
      numberless = create(:user, :senior, name: "Aunt", phone: nil)
      numberless.update!(phone: "+15558880000", call_consent_at: Time.current,
                         call_reminders_enabled: true)

      expect(numberless.reload.call_reminders_enabled).to be true
    end

    # An opt-out is about being telephoned, not about a particular number. A
    # caregiver must not be able to undo it by editing a field.
    it "does not lift an opt-out" do
      senior.update!(call_opted_out_at: Time.current)

      senior.update!(phone: "+15552220000")

      expect(senior.reload.call_opted_out_at).to be_present
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

  # The caregiver screen shows this so a wrong tz is visible to the one person
  # who would recognise it. within_calling_hours? cannot help there: a zone that
  # resolves and is simply wrong reads as permission and the guard stays quiet.
  describe "#local_time" do
    it "reads the clock where the senior is, not where the server is" do
      senior = build(:user, tz: "Asia/Tokyo")
      moment = ActiveSupport::TimeZone["America/New_York"].local(2026, 6, 15, 21, 30)

      expect(senior.local_time(at: moment).strftime("%-l:%M%P")).to eq("10:30am")
    end

    # The whole reason this returns nil instead of a Time: in_time_zone raises
    # ArgumentError on an unknown identifier, and the callers that need this are
    # the ones already handling a senior whose zone did not resolve.
    it "returns nil rather than raising when the zone cannot be resolved" do
      senior = build(:user, tz: "Neverwhere/Nowhere")

      expect { senior.local_time }.not_to raise_error
      expect(senior.local_time).to be_nil
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
