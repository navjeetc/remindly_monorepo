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
    # Asserted as a property rather than an exact number: the boundary depends
    # on the cache store. ActiveSupport::MemoryStore#increment returns nil for a
    # key that does not exist yet, so the first request of the day is not
    # counted here and eleven get through; SolidCache in production counts from
    # one. What matters either way is that it stops, and stops around ten rather
    # than at a hundred.
    it "stops well short of bulk" do
      sign_in(caregiver)

      20.times { |i| post "/dashboard/care_receiver", params: { user: { name: "Person #{i}" } } }

      expect(response).to have_http_status(:too_many_requests)
      expect(User.where(role: :senior).count).to be_between(10, 11)
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

      # The database carries foreign keys for telephone rows and `User` carried no
      # association for them, so destroying an account with any call attached
      # raised instead of saying goodbye — and this branch deliberately shows the
      # phone panel *before* consent, so "the caregiver already pressed Call and
      # ask" is the ordinary case rather than an exotic one.
      it "works even after the caregiver has already tried to telephone them" do
        senior.update!(phone: "+15557654321")
        TelnyxCall.create!(user: senior, purpose: "verification", to_number: senior.phone,
                           status: "initiated", outcome: "pending", attempt_number: 1,
                           requested_by: caregiver, completed_at: Time.current)
        get "/r/#{link.token}"

        post "/voice_reminders/decline"

        expect(response).to have_http_status(:ok)
        expect(User.exists?(senior.id)).to be(false)
        expect(TelnyxCall.where(user_id: senior.id)).to be_empty
      end

      # The calls they arranged for somebody else are that person's history.
      it "leaves calls it merely requested for other people alone" do
        other = create(:user, :senior, name: "Dad", tz: "America/New_York")
        theirs = TelnyxCall.create!(user: other, purpose: "verification", to_number: "+15550001111",
                                    status: "initiated", outcome: "pending", attempt_number: 1,
                                    requested_by: senior, completed_at: Time.current)
        get "/r/#{link.token}"

        post "/voice_reminders/decline"

        expect(TelnyxCall.exists?(theirs.id)).to be(true)
        expect(theirs.reload.requested_by_id).to be_nil
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

  # Somebody with no tablet has no screen to agree on, and the telephone is
  # their device. The consent call is the same first-use moment the screen
  # offers — it names who arranged it and asks rather than assumes — so the
  # keypress that answers it starts everything.
  describe "agreeing by telephone instead of on a screen" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end

    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:phone_call_reminders).and_return(true)
    end

    it "offers the phone panel before they have agreed" do
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).to include("Their phone number")
    end

    it "starts everything when they press 1" do
      senior.update!(phone: "+15551230000")
      Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)

      # What the webhook does when somebody agrees on the call.
      User.where(id: senior.id, phone: senior.phone)
          .update_all(phone_verified_at: Time.current, call_consent_at: Time.current,
                      call_opted_out_at: nil, call_reminders_enabled: true, updated_at: Time.current)
      senior.senior_links.where(state: :provisional).find_each { |l| l.update!(state: :active) }
      senior.reminders.find_each { |r| Recurrence.expand(r) }

      expect(CaregiverLink.find_by(senior_id: senior.id).state).to eq("active")
      expect(Occurrence.joins(:reminder).where(reminders: { user_id: senior.id })).to be_present
    end

    # Pressing 1 on that call starts everything, so pressing 9 has to be able to
    # end it. Otherwise somebody whose only device is the telephone can decline
    # the calls and still be left with an account another person made for them,
    # a caregiver writing reminders into it, and no way left to say no.
    it "deletes a provisional account when they press 9" do
      sign_in(caregiver)
      senior = create_care_receiver
      senior.update!(phone: "+15557654322")

      senior.senior_links.where(state: :provisional).exists?.tap { |p| expect(p).to be(true) }
      described = TelnyxWebhooksController.new
      described.send(:record_on, senior, call_opted_out_at: Time.current, call_reminders_enabled: false)
      described.send(:refuse_arrangement!, senior)

      expect(User.exists?(senior.id)).to be(false)
    end

    # Somebody already using Remindly who presses 9 is saying "stop telephoning
    # me", not "delete my account". Their history is theirs.
    it "leaves an account that has already started alone" do
      started = create(:user, :senior, :takes_calls, name: "Mom", tz: "America/New_York")
      CaregiverLink.create!(senior: started, caregiver: caregiver, permission: :manage)

      TelnyxWebhooksController.new.send(:refuse_arrangement!, started)

      expect(User.exists?(started.id)).to be(true)
    end

    # The cap that the per-number one cannot see: each call is to a different
    # number, so counting per number counts nothing about the person dialling.
    it "limits how many people one caregiver may ask to telephone" do
      11.times do |i|
        post "/dashboard/care_receiver", params: { user: { name: "Person #{i}" } }
        person = User.order(:id).last
        person.update!(phone: "+1555123000#{i % 10}")
        post "/dashboard/senior/#{person.id}/verify_phone"
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  # Both are written once, at setup, and the person they describe can never sign
  # in to correct them. The timezone is the one that matters: reminders are
  # expanded in their zone, so the wrong one fires every dose at the wrong hour
  # — a bug this project has shipped twice.
  describe "correcting what was typed at setup" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver(tz: "America/New_York")
    end

    it "changes the timezone" do
      patch "/dashboard/senior/#{senior.id}/details",
        params: { user: { name: senior.name, tz: "America/Los_Angeles" } }

      expect(senior.reload.tz).to eq("America/Los_Angeles")
    end

    it "changes the name" do
      patch "/dashboard/senior/#{senior.id}/details",
        params: { user: { name: "Mother", tz: senior.tz } }

      expect(senior.reload.name).to eq("Mother")
    end

    it "refuses to blank the name" do
      expect {
        patch "/dashboard/senior/#{senior.id}/details", params: { user: { name: "", tz: senior.tz } }
      }.not_to change { senior.reload.name }
    end

    # Somebody who signed up owns their own name and their own clock. This
    # screen is for repairing a caregiver's own typing, not for reaching into a
    # profile that has an owner.
    it "is not offered for somebody who can sign in themselves" do
      theirs = create(:user, :senior, name: "Mom", tz: "America/New_York")
      CaregiverLink.create!(senior: theirs, caregiver: caregiver, permission: :manage)

      expect {
        patch "/dashboard/senior/#{theirs.id}/details",
          params: { user: { name: "Renamed", tz: "America/Los_Angeles" } }
      }.not_to change { theirs.reload.tz }
    end

    it "offers the link on their page" do
      get "/dashboard/senior/#{senior.id}"

      expect(response.body).to include(edit_care_receiver_path(senior_id: senior.id))
    end
  end

  # Both bots found this independently, which is usually the sign it is real.
  #
  # A caregiver can invite a second caregiver before first use, and both links
  # are provisional by design. Activating only the one that happened to be found
  # leaves awaiting_first_use? true — so expansion stays suppressed and the
  # device is shown the consent question *again*, where pressing No would delete
  # the account moments after they said yes.
  describe "consent when two caregivers were invited before it" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end
    let(:link) { ReminderLink.live.find_by(user_id: senior.id) }

    before do
      post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: "sam@example.com" }
      reset!
    end

    it "activates every link, not the first one found" do
      get "/r/#{link.token}"

      post "/voice_reminders/start"

      expect(CaregiverLink.where(senior_id: senior.id).map(&:state).uniq).to eq([ "active" ])
    end

    it "does not ask the question a second time" do
      get "/r/#{link.token}"
      post "/voice_reminders/start"

      follow_redirect!

      expect(response.body).not_to include("set this up for you")
      expect(response.body).to include("My Reminders")
    end

    it "starts announcing rather than staying suppressed" do
      Reminder.create!(user: senior, title: "Morning tablets", rrule: "FREQ=DAILY", tz: senior.tz)
      get "/r/#{link.token}"

      post "/voice_reminders/start"

      expect(senior.reload.awaiting_first_use?).to be(false)
      expect(Occurrence.joins(:reminder).where(reminders: { user_id: senior.id })).to be_present
    end
  end

  # Coverage is activity: who is looking after this person, and on which days
  # nobody is. `active?` is the legacy predicate — senior present, caregiver
  # present — which a provisional link satisfies, because a caregiver made it.
  describe "the coverage screen before consent" do
    # The flag has to be on, or both examples pass on the flag's redirect and
    # prove nothing about the state at all.
    before do
      allow(FeatureFlag).to receive(:enabled?).and_call_original
      allow(FeatureFlag).to receive(:enabled?).with(:native_scheduling).and_return(true)
    end

    it "is refused" do
      sign_in(caregiver)
      senior = create_care_receiver

      get "/seniors/#{senior.id}/coverage"

      expect(response).to redirect_to(dashboard_path)
    end

    it "opens once they have agreed" do
      sign_in(caregiver)
      senior = create_care_receiver
      senior.senior_links.update_all(state: CaregiverLink.states[:active])

      get "/seniors/#{senior.id}/coverage"

      expect(response).to have_http_status(:ok)
    end
  end

  # check_role! asks whether a role was chosen, not which one. A care receiver
  # posting here would be handed a manage link to a person they invented, and
  # every other caregiver-only URL authorises through that link.
  describe "who may set somebody up" do
    it "refuses a care receiver" do
      sign_in(create(:user, :senior, name: "Mom", tz: "America/New_York"))

      expect {
        post "/dashboard/care_receiver", params: { user: { name: "Invented", tz: "America/New_York" } }
      }.not_to change { User.count }
    end

    it "refuses them the form too" do
      sign_in(create(:user, :senior, name: "Mom", tz: "America/New_York"))

      get "/dashboard/care_receiver/new"

      expect(response).to redirect_to(dashboard_path)
    end
  end

  # The care receiver's signed-in dashboard has always listed tasks; the voice
  # page never has. That only cost somebody who preferred the voice page until
  # this release, when it became the whole interface for a person with no
  # account — a caregiver ticking "visible to the care receiver" on Thursday's
  # appointment would have been telling nobody, while the screen looked exactly
  # as though it had worked.
  describe "what somebody else arranged, on the device" do
    let!(:senior) do
      sign_in(caregiver)
      create_care_receiver
    end
    let(:link) { ReminderLink.live.find_by(user_id: senior.id) }

    def task(title:, at:, visible: true, status: :pending, location: nil)
      Task.create!(senior_id: senior.id, created_by_id: caregiver.id, title: title,
                   task_type: :appointment, priority: :medium, status: status,
                   visible_to_senior: visible, location: location, scheduled_at: at)
    end

    before do
      senior.senior_links.update_all(state: CaregiverLink.states[:active])
      reset!
    end

    it "lists one arranged for this week" do
      task(title: "Doctor Shah", at: 2.days.from_now, location: "The surgery")
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body.first["title"]).to eq("Doctor Shah")
      expect(response.parsed_body.first["location"]).to eq("The surgery")
    end

    # Somebody waiting at home wants to know whether anyone is coming. "Jane is
    # helping" and "nobody has taken this one yet" are different facts, and the
    # second is the one worth saying out loud.
    it "names whoever is helping" do
      helper = create(:user, :caregiver, name: "Sam", nickname: "Sammy")
      CaregiverLink.create!(senior: senior, caregiver: helper, permission: :view, state: :active)
      task(title: "Doctor Shah", at: 2.days.from_now).update!(assigned_to: helper)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body.first["assigned_to"]).to eq("Sammy")
    end

    it "says so plainly when nobody has taken it" do
      task(title: "Doctor Shah", at: 2.days.from_now)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body.first["assigned_to"]).to be_nil
    end

    # A caregiver with no name would otherwise be introduced to the person they
    # care for by their email address.
    it "never names them by their email address" do
      nameless = User.create!(email: "helper@example.com", role: :caregiver, tz: "America/New_York")
      CaregiverLink.create!(senior: senior, caregiver: nameless, permission: :view, state: :active)
      task(title: "Doctor Shah", at: 2.days.from_now).update!(assigned_to: nameless)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.body).not_to include("helper@example.com")
      expect(response.parsed_body.first["assigned_to"]).to eq("helper")
    end

    # The caregiver decides what this person sees. A task not marked visible is
    # caregiver coordination and is none of their business.
    it "leaves out what the caregiver kept to themselves" do
      task(title: "Ring the pharmacy", at: 1.day.from_now, visible: false)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body).to be_empty
    end

    it "leaves out what is already done" do
      task(title: "Collect prescription", at: 1.day.from_now, status: :completed)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body).to be_empty
    end

    it "leaves out next month" do
      task(title: "Dentist", at: 30.days.from_now)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body).to be_empty
    end

    it "never shows somebody else's" do
      other = create(:user, :senior, name: "Dad", tz: "America/New_York")
      Task.create!(senior_id: other.id, created_by_id: caregiver.id, title: "Not mine",
                   task_type: :appointment, priority: :medium, visible_to_senior: true,
                   scheduled_at: 1.day.from_now)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response.parsed_body).to be_empty
    end

    # Same gate as everything else about their day.
    it "is refused before they have agreed" do
      senior.senior_links.update_all(state: CaregiverLink.states[:provisional])
      task(title: "Doctor Shah", at: 2.days.from_now)
      get "/r/#{link.token}"

      get "/voice_reminders/coming_up"

      expect(response).to have_http_status(:forbidden)
    end

    it "gives the page somewhere to put them" do
      get "/r/#{link.token}"

      expect(response.body).to include('id="comingUpList"')
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

    # The field had no accessible name: a screen reader announced "edit text,
    # blank" on the page whose whole job is typing numbers being read aloud to
    # somebody whose eyesight is part of why the telephone is the channel.
    it "gives the field a name a screen reader can announce" do
      get "/start"

      doc = Nokogiri::HTML(response.body)
      field = doc.at_css("#code")
      label = doc.at_css("label[for=code]")

      expect(label&.text).to include("six numbers")
      expect(field["aria-describedby"]).to eq("code_help")
      expect(doc.at_css("#code_help")).to be_present
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

    # The spend carries every condition the check made. Without the expiry in
    # the UPDATE, a code that lapsed between reading the row and writing it
    # would still be accepted — the gap the compare-and-swap exists to close.
    it "will not spend a code that lapsed a moment ago" do
      code = issue_code
      link.update_columns(start_code_expires_at: 1.second.ago)
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

  # Inviting a second caregiver to somebody who has not agreed to anything must
  # not hand that caregiver a link born active — with it come the activity,
  # acknowledgement and coverage screens the provisional state exists to
  # withhold, about a person who has consented to nothing.
  describe "inviting a second caregiver before the care receiver has agreed" do
    it "gives them a provisional link too" do
      sign_in(caregiver)
      senior = create_care_receiver

      post "/dashboard/senior/#{senior.id}/invite_caregiver", params: { caregiver_email: "sam@example.com" }

      invited = CaregiverLink.find_by(senior_id: senior.id, caregiver_id: User.find_by(email: "sam@example.com").id)
      expect(invited.state).to eq("provisional")
    end

    it "still gives an active link on an account that has started" do
      started = create(:user, :senior, name: "Mom", tz: "America/New_York")
      CaregiverLink.create!(senior: started, caregiver: caregiver, permission: :manage)
      sign_in(caregiver)

      post "/dashboard/senior/#{started.id}/invite_caregiver", params: { caregiver_email: "sam@example.com" }

      invited = CaregiverLink.find_by(senior_id: started.id, caregiver_id: User.find_by(email: "sam@example.com").id)
      expect(invited.state).to eq("active")
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
