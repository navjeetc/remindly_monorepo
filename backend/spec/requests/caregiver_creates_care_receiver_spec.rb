# frozen_string_literal: true

require "rails_helper"

# Phase 3: a caregiver sets up the person they are setting Remindly up for.
#
# Removing the pairing step is not merely removing friction. Until now consent
# was structural — access could not exist unless the person receiving reminders
# generated a token and handed it over — and a monitoring tool set up on
# somebody without their knowledge is a recognised pattern in elder abuse. The
# old design prevented that by accident. This one has to prevent it on purpose.
#
# So consent moves from before setup to first use, and these specs are where
# that claim is kept honest: what a caregiver may do before the care receiver
# has agreed, what they may not, and what happens when the answer is no.
RSpec.describe "A caregiver setting somebody up", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:caregiver) { create(:user, :caregiver, name: "Jane") }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # CaregiverDashboardController is an API controller: it authenticates by
  # Bearer token, not by the session the dashboard pages use. A spec that signs
  # in and calls it gets a 401 and proves nothing about the state gate.
  def bearer(user)
    { "Authorization" => "Bearer #{JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i },
                                              ENV.fetch('JWT_SECRET', 'dev_secret_change_me'), 'HS256')}" }
  end

  def create_care_receiver(name: "Mum", tz: "America/New_York")
    post "/dashboard/care_receiver", params: { user: { name: name, tz: tz } }
    User.order(:id).last
  end

  describe "creating the account" do
    before { sign_in(caregiver) }

    it "makes a care receiver with no email address at all" do
      senior = create_care_receiver

      expect(senior.role).to eq("senior")
      expect(senior.email).to be_nil
      expect(senior.name).to eq("Mum")
    end

    # With no address there is no lookup, so this form cannot be used to find
    # out who already has an account — and nothing will ever try to reach this
    # person by email, which a nil address alone would not guarantee.
    it "makes them structurally unmailable" do
      expect(create_care_receiver.email_deliverable?).to be(false)
    end

    it "links the caregiver who created them, able to make changes" do
      senior = create_care_receiver
      link = CaregiverLink.find_by(senior_id: senior.id, caregiver_id: caregiver.id)

      expect(link.permission).to eq("manage")
      expect(link.state).to eq("provisional")
    end

    it "mints the link their device will use" do
      senior = create_care_receiver

      expect(ReminderLink.live.where(user_id: senior.id).count).to eq(1)
    end

    # Reminder times are expanded in this zone. A caregiver three timezones away
    # who leaves their own here would have every dose fire at the wrong hour —
    # the clock bug this project has already had twice.
    it "keeps the timezone the caregiver chose for them" do
      expect(create_care_receiver(tz: "America/Los_Angeles").tz).to eq("America/Los_Angeles")
    end

    it "refuses to create somebody with no name" do
      expect { create_care_receiver(name: "") }.not_to change { User.count }
    end
  end

  # Invariant 6: a caregiver cannot create accounts in bulk. A household setting
  # up two parents in an afternoon is normal; a script making hundreds of people
  # is not a caregiver, and every one of those people would be a real account
  # somebody could then be told to open a link for.
  #
  # This is only testable because the test cache is now a memory store — against
  # the null store it used to be, every rate limit in the application counted
  # nothing and this example would have passed while proving nothing.
  describe "how many can be created" do
    it "stops well short of bulk" do
      sign_in(caregiver)

      12.times { |i| post "/dashboard/care_receiver", params: { user: { name: "Person #{i}" } } }

      expect(User.where(role: :senior).count).to eq(10)
      expect(response).to have_http_status(:too_many_requests)
    end

    # Per caregiver, not per IP: two people setting up their own parents from
    # the same house should not spend each other's allowance.
    it "counts each caregiver separately" do
      sign_in(caregiver)
      10.times { |i| post "/dashboard/care_receiver", params: { user: { name: "Person #{i}" } } }

      reset!
      sign_in(create(:user, :caregiver, name: "Sam"))
      post "/dashboard/care_receiver", params: { user: { name: "Sam's mum" } }

      expect(response).to redirect_to(senior_dashboard_path(User.order(:id).last))
    end
  end

  # The heart of it. A provisional account is one the person it describes has
  # not agreed to, so nothing about their day may be shown to anybody.
  describe "before the care receiver has agreed" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end

    it "lets the caregiver write reminders" do
      post "/dashboard/senior/#{senior.id}/reminder", params: {
        reminder: { title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz }
      }

      expect(senior.reminders.count).to eq(1)
    end

    it "shows the caregiver that it has not started, rather than an empty day" do
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).to include("Waiting for them to start")
      expect(response.body).not_to include("7-Day Activity History")
    end

    # The route refuses rather than the query happening to return nothing —
    # the difference between a guarantee and a coincidence.
    %w[activity today missed_count].each do |endpoint|
      it "refuses the #{endpoint} endpoint" do
        get "/caregiver_dashboard/#{senior.id}/#{endpoint}", headers: bearer(caregiver)

        expect(response).to have_http_status(:forbidden)
      end
    end

    # An occurrence is a record about a person, and the missed sweep turns it
    # into a claim: "Mum missed her morning tablets", emailed to the caregiver,
    # about somebody who has never seen the device. The account is set up on
    # Monday and the tablet arrives on Friday.
    it "records nothing about a person who has not agreed" do
      post "/dashboard/senior/#{senior.id}/reminder", params: {
        reminder: { title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz }
      }

      expect(Occurrence.joins(:reminder).where(reminders: { user_id: senior.id })).to be_empty
    end

    it "tells the caregiver nothing about their day, even by email" do
      reminder = Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY",
                                  tz: senior.tz, category: :medication)
      Occurrence.create!(reminder: reminder, scheduled_at: 3.hours.ago, status: :pending)

      expect(ReminderNotificationService.recipients(reminder)).to be_empty
    end

    it "announces nothing on the device" do
      link = ReminderLink.live.find_by(user_id: senior.id)
      reset!
      get "/r/#{link.token}"

      get "/voice_reminders/today"

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the first thing the care receiver sees" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end
    let(:link) { ReminderLink.live.find_by(user_id: senior.id) }

    before { reset! }

    # Naming the person who arranged it is the anti-scam move: it is the one
    # thing a stranger could not know, and it is what tells somebody whether
    # this is their daughter or a confidence trick.
    it "names who set it up, and offers refusal" do
      get "/r/#{link.token}"

      expect(response.body).to include("Jane set this up for you")
      expect(response.body).to include("Yes, start my reminders")
      expect(response.body).to include("No thank you")
    end

    it "does not show the reminders yet" do
      Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)
      get "/r/#{link.token}"

      expect(response.body).not_to include("Morning tablets")
    end

    describe "saying yes" do
      it "starts everything" do
        get "/r/#{link.token}"

        post "/voice_reminders/start"

        expect(CaregiverLink.find_by(senior_id: senior.id).state).to eq("active")
      end

      # Back to the address worth bookmarking, not the tidier one. Somebody
      # bookmarks what is on screen after they press Yes, and /voice_reminders
      # works only while the cookie lives — the failure this whole feature
      # exists to end.
      it "lands back on the address worth bookmarking" do
        get "/r/#{link.token}"

        post "/voice_reminders/start"

        expect(response).to redirect_to(reminder_link_path(token: link.token))
      end

      # Reminders written while waiting exist as a schedule and not yet as a
      # day, because expansion is refused for an account nobody has agreed to.
      # Saying yes has to catch them up, or the first dose arrives whenever the
      # hourly sweep next runs.
      it "materialises the day that was written while waiting" do
        Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)
        expect(Occurrence.joins(:reminder).where(reminders: { user_id: senior.id })).to be_empty

        get "/r/#{link.token}"
        post "/voice_reminders/start"

        expect(Occurrence.joins(:reminder).where(reminders: { user_id: senior.id })).to be_present
      end

      it "lets the device hear reminders from then on" do
        get "/r/#{link.token}"
        post "/voice_reminders/start"

        get "/voice_reminders/today"

        expect(response).to have_http_status(:ok)
      end

      it "lets the caregiver see their day from then on" do
        get "/r/#{link.token}"
        post "/voice_reminders/start"

        get "/caregiver_dashboard/#{senior.id}/activity", headers: bearer(caregiver)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "saying no" do
      # Destroying the account is safe for a structural reason rather than a
      # careful one: a provisional account can only ever contain reminders the
      # caregiver typed. There is nothing of this person's in it, because they
      # have never used it.
      it "deletes the account and everything set up for them" do
        Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)
        get "/r/#{link.token}"

        post "/voice_reminders/decline"

        expect(User.exists?(senior.id)).to be(false)
        expect(Reminder.where(user_id: senior.id)).to be_empty
        expect(ReminderLink.where(user_id: senior.id)).to be_empty
        expect(CaregiverLink.where(senior_id: senior.id)).to be_empty
      end

      it "says so, once" do
        get "/r/#{link.token}"

        post "/voice_reminders/decline"

        expect(response.body).to include("That's all deleted")
      end

      it "leaves the link dead behind it" do
        get "/r/#{link.token}"
        token = link.token
        post "/voice_reminders/decline"

        get "/r/#{token}"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # The credential a view-only caregiver must not be handed, in either of its
  # forms. The address was gated when phase 2 made a link able to write; the six
  # digits are the same credential said out loud, and were not.
  describe "what a caregiver who may only look can see" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end
    let(:link) { ReminderLink.live.find_by(user_id: senior.id) }
    let(:looker) { create(:user, :caregiver, name: "Sam") }

    before do
      CaregiverLink.create!(senior: senior, caregiver: looker, permission: :view, state: :active)
      post "/dashboard/senior/#{senior.id}/reminder_link/#{link.id}/start_code"
      reset!
      sign_in(looker)
    end

    it "is not shown the address" do
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).not_to include(link.reload.token)
    end

    # Typed at /start these six digits hand over a cookie that can mark doses
    # done. Reading them off a screen is copy and paste with extra steps.
    it "is not shown the six-digit code" do
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).not_to include(link.reload.start_code)
    end

    it "cannot issue one either" do
      expect {
        post "/dashboard/senior/#{senior.id}/reminder_link/#{link.id}/start_code"
      }.not_to change { link.reload.start_code }
    end
  end

  # A blank email address is no longer a typo, it is a real state — so a lookup
  # by a missing one must refuse rather than match whichever care receiver the
  # database returns first.
  describe "signing in with no address" do
    it "refuses rather than matching a care receiver who has none" do
      sign_in(caregiver)
      created = create_care_receiver
      reset!

      expect {
        post "/login/magic", params: {}
      }.not_to change { ActionMailer::Base.deliveries.count }

      expect(created.reload.email).to be_nil
    end
  end

  # Six digits, read down a telephone. The one channel this audience is
  # comfortable with: every other remote option asks an older person to find a
  # message in an inbox and trust a link inside it.
  describe "setting up over the telephone" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end
    let(:link) { ReminderLink.live.find_by(user_id: senior.id) }

    def issue_code
      post "/dashboard/senior/#{senior.id}/reminder_link/#{link.id}/start_code"
      link.reload.start_code
    end

    # Instructions for what exists. The first version told a caregiver to read
    # out "the six-digit code" the moment the account was created, when no code
    # had been generated and the button that makes one was still unpressed.
    it "does not mention a code before there is one" do
      reset!
      sign_in(caregiver)
      other = create_care_receiver(name: "Dad")

      get "/dashboard/senior/#{other.id}"

      expect(response.body).to include("Set up over the phone")
      expect(response.body).not_to match(/read them the six-digit code/i)
    end

    # The host somebody is actually using, not a literal: in development this
    # was telling people to visit remindly.care, which is not where they are.
    it "names the host the caregiver is on" do
      issue_code

      get "/dashboard/senior/#{senior.id}"

      expect(response.body).to include("www.example.com/start")
    end

    it "shows the caregiver six digits to read out" do
      code = issue_code

      expect(code).to match(/\A\d{6}\z/)
      get "/dashboard/senior/#{senior.id}"
      expect(response.body).to include(code)
    end

    it "lets the care receiver's device in with them" do
      code = issue_code
      reset!

      post "/start", params: { code: code }

      expect(response).to redirect_to(reminder_link_path(token: link.token))
    end

    # The device lands on the address it should bookmark, not on a tidier one —
    # the same reason /r/:token renders rather than redirecting.
    it "lands on the address worth bookmarking" do
      code = issue_code
      reset!
      post "/start", params: { code: code }

      follow_redirect!

      expect(response.body).to include("set this up for you")
    end

    # Single use. A code that still worked after somebody used it would be a
    # secret left lying about on a screen, and a code read over a speakerphone
    # is heard by whoever is in the room.
    it "cannot be used twice" do
      code = issue_code
      reset!
      post "/start", params: { code: code }
      reset!

      post "/start", params: { code: code }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "stops working after ten minutes" do
      code = issue_code
      reset!

      travel(11.minutes) { post "/start", params: { code: code } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # No enumeration signal: a wrong code, an expired one and a spent one are
    # answered identically, so guessing tells you nothing about how close you
    # were.
    it "answers a wrong code exactly as it answers an expired one" do
      code = issue_code
      reset!
      travel(11.minutes) { post "/start", params: { code: code } }
      expired = [ response.status, response.body ]
      reset!

      post "/start", params: { code: "000000" }

      expect([ response.status, response.body ]).to eq(expired)
    end

    it "does not let a code into a revoked link" do
      code = issue_code
      link.revoke!
      reset!

      post "/start", params: { code: code }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # An account the care receiver started themselves, by handing over a token,
  # is consent given before setup rather than at first use — so it must not be
  # asked again.
  describe "somebody who paired the old way" do
    it "is never shown the first-run question" do
      senior = create(:user, :senior, name: "Mom", tz: "America/New_York")
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
      link = ReminderLink.mint(user: senior)

      get "/r/#{link.token}"

      expect(response.body).not_to include("set this up for you")
      expect(response.body).to include("My Reminders")
    end
  end
end
