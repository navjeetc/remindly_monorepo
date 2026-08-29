require "rails_helper"

# "Senior" narrows the product to a subset of the people it serves — a caregiver
# reviewing Remindly asked for a word that does not assume age, since not
# everyone being cared for is old.
#
# The stored value is untouched. `senior` is in the role enum, in four foreign
# keys and in most of this suite, and renaming it would migrate data to change a
# word nobody stores for its own sake. So the split these specs hold is: the
# database says senior, the screen says care receiver.
RSpec.describe "Care receiver terminology", type: :request do
  let(:caregiver) { create(:user, :caregiver, name: "Jane") }
  let(:senior) { create(:user, :senior, name: "Mom") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  # Script and style contents are stripped before matching. Nokogiri's #text
  # includes them, so JavaScript comments explaining @senior's timezone counted
  # as words on the page — they are code, and the code keeps its names.
  def page_text
    doc = Nokogiri::HTML(response.body)
    doc.css("script, style").each(&:remove)
    doc.text.gsub(/\s+/, " ")
  end

  describe "the role label" do
    it "reads as care receiver while the stored value stays senior" do
      expect(senior.role).to eq("senior")
      expect(senior.role_label).to eq("Care receiver")
    end

    it "leaves the other roles alone" do
      expect(caregiver.role_label).to eq("Caregiver")
      expect(create(:user, :admin, name: "Root").role_label).to eq("Admin")
    end

    # Renaming the enum would have meant a migration. This is the check that the
    # cheaper route actually reaches the screen.
    it "shows on the profile instead of the raw role" do
      sign_in(senior)
      get "/profile"

      expect(page_text).to include("Care receiver")
      expect(page_text).not_to match(/\bSenior\b/)
    end

    # This used to check that the switch destination was labelled rather than
    # printed raw — a caregiver was offered a "switch to senior". The switch
    # itself has since been removed, so what is left to hold is that the page
    # states the role without the stored word appearing anywhere.
    it "states a caregiver's role without saying senior" do
      sign_in(caregiver)
      get "/profile"

      expect(page_text).to include("You're set up as a caregiver")
      expect(page_text).not_to match(/\bsenior\b/i)
    end
  end

  describe "the signed-in app" do
    it "does not call anyone a senior on the caregiver's dashboard" do
      sign_in(caregiver)
      get "/dashboard"

      expect(page_text).not_to match(/\bseniors?\b/i)
    end

    it "does not call anyone a senior on the task form" do
      sign_in(caregiver)
      get "/seniors/#{senior.id}/tasks/new"

      expect(page_text).not_to match(/\bseniors?\b/i)
    end

    it "does not call anyone a senior when pairing" do
      sign_in(caregiver)
      get "/dashboard/pair"

      expect(page_text).not_to match(/\bseniors?\b/i)
    end
  end

  # The public pages are split on purpose. Body copy is broadened so a
  # forty-five-year-old caring for a disabled spouse does not bounce off a page
  # that only talks about seniors — but the title, description and og tags keep
  # the word, because that is what people type into a search box. Nobody
  # searches for a "care receiver app". Meet them where they search, then do not
  # exclude them once they arrive.
  # Found by looking at the screen rather than the diff: the empty state served
  # both roles but only ever offered the caregiver's action, so a care receiver
  # with nobody linked was told to "pair with a care receiver" and sent to a form
  # asking for a token only a caregiver would hold. It said "Pair with Senior"
  # before the rename, which was wrong in the same way and easier to miss.
  describe "the empty dashboard" do
    it "asks a care receiver to generate a token, which is their half of pairing" do
      # Unlinked on purpose — the block only renders for somebody with nobody
      # linked, which is exactly the person who needs telling what to do.
      alone = create(:user, :senior, name: "Nora")
      sign_in(alone)
      get "/dashboard"

      expect(page_text).to include("No caregivers yet")
      expect(page_text).to include("Generate Pairing Token")
      expect(page_text).not_to include("Pair with a care receiver")
    end

    # The empty state explains the action; the header only names it. Showing
    # both puts two identical blue buttons on an otherwise empty page, and the
    # one without the explanation is the louder of the two.
    it "offers the action once, not twice" do
      alone = create(:user, :senior, name: "Nora")
      sign_in(alone)
      get "/dashboard"

      expect(page_text.scan("Generate Pairing Token").length).to eq(1)
    end

    it "still offers it in the header once somebody is linked" do
      sign_in(senior)
      get "/dashboard"

      expect(page_text).to include("Generate Pairing Token")
      expect(page_text).not_to include("No caregivers yet")
    end

    it "asks a caregiver to enter one, which is theirs" do
      unlinked = create(:user, :caregiver, name: "Sam")
      sign_in(unlinked)
      get "/dashboard"

      expect(page_text.scan("Pair with a care receiver").length).to eq(1)
      expect(page_text).not_to include("Generate Pairing Token")
    end
  end

  describe "inviting somebody who cannot be a caregiver" do
    # A user exists from their first sign-in and chooses a role afterwards, so a
    # blank role is an ordinary state, not a corrupt one. role_label falls back
    # to titleize, which turns nil into "" — and the sentence read "They are
    # currently a ."
    it "says so plainly when they have not chosen a role yet" do
      roleless = User.create!(email: "nobody@example.com", name: "Sam")
      sign_in(caregiver)

      post "/dashboard/senior/#{senior.id}/invite_caregiver",
        params: { caregiver_email: roleless.email }

      expect(flash[:alert]).to include("has not chosen a role yet")
      expect(flash[:alert]).not_to match(/currently a \./)
    end

    it "names the role when they have one" do
      other = create(:user, :senior, name: "Pat", email: "pat@example.com")
      sign_in(caregiver)

      post "/dashboard/senior/#{senior.id}/invite_caregiver",
        params: { caregiver_email: other.email }

      expect(flash[:alert]).to include("currently a care receiver")
    end
  end

  # The admin filter submits the stored role, so anything that titleizes it
  # prints "Senior" no matter how the option beside it is labelled. The badge in
  # the same list was converted; this header was not, and sat two lines away.
  describe "the admin user list" do
    it "heads a filtered list with the label, not the stored value" do
      sign_in(create(:user, :admin, name: "Root"))
      get "/admin/users", params: { role_filter: "senior" }

      expect(page_text).to include("Care receiver Users")
      expect(page_text).not_to match(/\bSenior\b/)
    end
  end

  describe "the public pages" do
    it "no longer says senior in the How To prose" do
      get "/how_to"

      body = Nokogiri::HTML(response.body)
      body.css("script, style, title, head").each(&:remove)

      expect(body.text.gsub(/\s+/, " ")).not_to match(/\bseniors?\b/i)
    end

    it "keeps the search terms in the metadata, which is where they earn their keep" do
      get "/how_to"

      expect(Nokogiri::HTML(response.body).at_css("title").text).to match(/seniors/i)
    end

    it "does not call anyone a senior in the terms" do
      get "/terms"

      body = Nokogiri::HTML(response.body)
      body.css("script, style, title, head").each(&:remove)

      expect(body.text.gsub(/\s+/, " ")).not_to match(/\bseniors?\b/i)
    end
  end
end
