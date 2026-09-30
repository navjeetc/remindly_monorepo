# frozen_string_literal: true

require "rails_helper"

# Every box a person types into or picks from wears the one `field` style
# (app/views/shared/_ui_styles.css.erb, described in docs/UI_STYLE_GUIDE.md).
#
# How this came about, twice. First every text field was invisible: the markup
# said `border-gray-300`, a border colour, and never `border`, the width, and
# Tailwind's reset sets the width to 0. Then, with borders restored, fields were
# still a dozen variants of a 1px light-grey line with no padding: a caregiver
# typed a reminder's title into the notes, and drop-downs read as plain text.
# Each form had been styled by hand, so each fix reached one form and missed
# the others.
#
# So the rule is checked in the source, across every view, rather than page by
# page, and a new form that skips it fails here. Nothing else would catch it:
# nothing errors, nothing logs, and the page looks deliberate.
RSpec.describe "The fields a person types into, and the buttons beside them" do
  VIEWS = Rails.root.join("app/views")

  # Each exemption says why it is not a `field`. Add to this only with a reason
  # that would satisfy the person who has to find the box.
  EXEMPT = {
    # Public marketing pages load no dashboard CSS by design (see PublicPage);
    # the mailing-list box has its own 2px border and padding in that layout.
    "shared/_subscribe_form.html.erb" => "marketing layout styles its own inputs",
    # The six-digit code a care receiver types, alone on the page and already
    # far larger than any field.
    "start/show.html.erb" => "deliberately oversized single field",
    # The development-only user switcher in the nav, never seen in production.
    "layouts/dashboard.html.erb" => "dev-only control"
  }.freeze

  HELPERS = %w[
    text_field text_area email_field telephone_field phone_field number_field
    time_field date_field datetime_local_field password_field url_field search_field
    select time_zone_select collection_select
  ].flat_map { |h| [ h, "#{h}_tag" ] }.join("|")

  NOT_TYPED_INTO = %w[hidden submit checkbox radio button range file].freeze

  # [file, line, snippet] for every field in the views without the class.
  def unstyled_fields
    Dir[VIEWS.join("**/*.erb")].sort.flat_map do |path|
      relative = Pathname(path).relative_path_from(VIEWS).to_s
      next [] if EXEMPT.key?(relative)

      source = File.read(path)
      found = []

      source.scan(/<%=\s*(?:\w+\.)?(?:#{HELPERS})\b.*?%>/m) do
        call = Regexp.last_match
        found << [ relative, call.begin(0), call[0] ] unless call[0] =~ /class:\s*["'](?:[^"']*\s)?field[\s"']/
      end

      # A tag may hold ERB, so `%>` does not end it.
      source.scan(/<(?:input|select|textarea)\b(?:<%.*?%>|[^>])*>/m) do
        tag = Regexp.last_match
        type = tag[0][/\stype="(\w+)"/, 1]
        next if NOT_TYPED_INTO.include?(type)

        found << [ relative, tag.begin(0), tag[0] ] unless tag[0] =~ /class="(?:[^"]*\s)?field[\s"]/
      end

      found.map { |file, offset, text| "#{file}:#{source[0...offset].count("\n") + 1}  #{text.squish.truncate(90)}" }
    end
  end

  it "gives every field in every view the field style" do
    expect(unstyled_fields).to be_empty, "fields without class \"field\":\n#{unstyled_fields.join("\n")}"
  end

  # The other half of the same confusion: buttons drawn as a white box with a
  # grey border are what a field looks like, and "Replace this link" and "Stop
  # this link" were taken for form fields. Anything styled as a button uses
  # `button` plus exactly one filled variant, so there is one place that
  # decides what a button looks like.
  BUTTON_VARIANTS = %w[button-primary button-secondary button-danger].freeze

  # The public pages have their own inline CSS and their own .btn classes
  # (see PublicPage); the dashboard's styles never load there.
  # Emails carry their own inline styles too, and their `button` class is
  # theirs.
  MARKETING = %r{\A(pages/|posts/|subscribers/|shared/_subscribe_form|layouts/marketing|layouts/mailer|[a-z_]+_mailer/)}

  # Controls that are deliberately not ordinary buttons, matched by a piece
  # of their source. Each is filled or oversized, so none can pass for a field.
  CUSTOM_CONTROLS = {
    "caregiver_availabilities/index.html.erb" => {
      "showView(" => "List/Calendar switch whose halves are recoloured by script"
    },
    "caregiver_availabilities/bulk_new.html.erb" => {
      "onclick=\"select" => "small quick-pick chips that tick groups of dates",
      "onclick=\"clear" => "small quick-pick chip that clears the dates"
    },
    "dashboard/choose_role.html.erb" => {
      "select_role_path" => "two large cards, a heading over a sentence"
    },
    "dashboard/how_to.html.erb" => {
      "bg-green-600" => "coloured to match the care receiver section it sits in",
      "bg-purple-600" => "coloured to match the caregiver section it sits in"
    },
    "dashboard/index.html.erb" => {
      "Check Coverage Gaps" => "development-only trigger, never in production"
    },
    "tasks/show.html.erb" => {
      "Mark Complete" => "green for the good outcome, beside Start Task, which is the blue primary"
    }
  }.freeze

  def styled_as_button?(classes)
    return true if classes.include?("button") || classes.any? { |c| c.start_with?("btn") }

    classes.any? { |c| c.start_with?("px-", "py-") } &&
      classes.any? { |c| c.start_with?("bg-", "border") } &&
      classes.any? { |c| c.start_with?("rounded") }
  end

  def buttons_off_contract
    Dir[VIEWS.join("**/*.erb")].sort.flat_map do |path|
      relative = Pathname(path).relative_path_from(VIEWS).to_s
      next [] if relative.match?(MARKETING)

      source = File.read(path)
      custom = CUSTOM_CONTROLS.fetch(relative, {})
      found = []
      pattern = /<%=\s*(?:\w+\.)?(?:link_to|button_to|submit|submit_tag|button_tag)\b.*?%>|<(?:button|a)\b(?:<%.*?%>|[^>])*>/m
      source.scan(pattern) do
        element = Regexp.last_match
        classes = element[0][/class(?::\s*|=)["']([^"']*)["']/, 1].to_s.split
        next unless styled_as_button?(classes)
        next if custom.keys.any? { |marker| element[0].include?(marker) }
        next if classes.include?("button") && (classes & BUTTON_VARIANTS).one? && classes.none? { |c| c.start_with?("btn") }

        found << "#{relative}:#{source[0...element.begin(0)].count("\n") + 1}  #{element[0].squish.truncate(90)}"
      end
      found
    end
  end

  it "styles every button with button and one variant" do
    expect(buttons_off_contract).to be_empty, "buttons off the shared style:\n#{buttons_off_contract.join("\n")}"
  end

  # No layout loads Turbo or Rails UJS, so a data-confirm or data-turbo-confirm
  # is never read: Delete Reminder, Delete Task, Unlink and Disconnect all
  # acted on one click while looking as if they would ask. Destructive
  # buttons confirm with a plain onclick instead (docs/UI_STYLE_GUIDE.md).
  it "asks for confirmation in a way the page can actually run" do
    inert = Dir[VIEWS.join("**/*.erb")].sort.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next unless line.match?(/data-(turbo-)?confirm=|data:\s*\{[^}]*\b(turbo_)?confirm:/)

        "#{Pathname(path).relative_path_from(VIEWS)}:#{index + 1}  #{line.strip.truncate(90)}"
      end
    end

    expect(inert).to be_empty, "confirmations nothing will show:\n#{inert.join("\n")}"
  end

  # A label says what its control does, in words. "✅ Active" put a green tick
  # beside a checkbox, which is a second checkmark when the box is ticked and a
  # contradiction when it is not.
  it "puts no emoji in a label" do
    labelled = Dir[VIEWS.join("**/*.erb")].sort.flat_map do |path|
      source = File.read(path)
      labels = source.scan(/<%=\s*(?:\w+\.)?label(?:_tag)?\b[^%]*?\bdo\s*%>.*?<% end %>|<%=\s*(?:\w+\.)?label(?:_tag)?\b.*?%>|<label\b.*?<\/label>/m)
      labels.select { |label| label.match?(/\p{Extended_Pictographic}/) }
            .map { |label| "#{Pathname(path).relative_path_from(VIEWS)}  #{label.squish.truncate(80)}" }
    end

    expect(labelled).to be_empty, "labels with emoji:\n#{labelled.join("\n")}"
  end

  # The class is worth nothing if a layout does not carry the rules behind it.
  describe "on the pages that have fields", type: :request do
    let(:caregiver) { create(:user, :caregiver, name: "Jane") }
    let(:senior) { create(:user, :senior, name: "Mom", tz: "America/New_York") }

    def field_rules_present?
      Nokogiri::HTML(response.body).css("style").any? { |style| style.text.include?(".field {") }
    end

    it "ships the rules on the sign-in page" do
      get "/login"

      expect(field_rules_present?).to be(true)
    end

    it "ships the rules on dashboard pages and uses them on the reminder form" do
      CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
      post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      get "/dashboard/senior/#{senior.id}/reminder/new"

      expect(field_rules_present?).to be(true)
      page = Nokogiri::HTML(response.body)
      %w[input[name='reminder[title]'] textarea[name='reminder[notes]'] select[name='reminder[category]']
         input[name='reminder[time]'] select[name='reminder[frequency]']].each do |selector|
        expect(page.at_css(selector)["class"].split).to include("field"), selector
      end
    end

    it "ships the rules on the care receiver's voice page" do
      post "/magic/verify", params: { token: senior.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

      get "/voice_reminders"
      follow_redirect! if response.redirect?

      expect(field_rules_present?).to be(true)
    end
  end
end
