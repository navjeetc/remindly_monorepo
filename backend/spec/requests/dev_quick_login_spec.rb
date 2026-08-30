require "rails_helper"

# The two dev shortcuts on the sign-in page named a role and passed an email,
# trusting the seed data to agree about what those accounts are. It does not:
# caregiver@example.com holds the care receiver role and senior@example.com
# holds the caregiver one, so each button signed you in as the thing the other
# one promised. Reported from a phone, where "clicking caregiver logs in as care
# receiver and vice versa" is exactly what it looked like.
RSpec.describe "The development quick-login buttons", type: :request do
  # Named to mirror the crossed fixtures that caused this, so the specs fail if
  # somebody "fixes" the lookup by trusting the address again.
  let!(:crossed_caregiver_address) { create(:user, :senior, name: "Wrongly Named", email: "caregiver@example.com") }
  let!(:crossed_senior_address) { create(:user, :caregiver, name: "Also Wrong", email: "senior@example.com") }

  # Both the buttons and the action are gated on development, and specs run in
  # test — without this the page renders no buttons and dev_login refuses, so
  # every example here would pass against a broken implementation by never
  # reaching it.
  before do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
  end

  # Asserted through the profile rather than the dashboard. Stubbing the
  # environment makes the dashboard render its development-only controls, and
  # one of those points at a route that only exists in development — so
  # following the redirect there raised on a missing helper rather than telling
  # us who had signed in.
  def signed_in_role
    get "/profile"
    text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")
    text[/You're set up as an? ([a-z ]+)/, 1]&.strip
  end

  it "signs in an actual caregiver when asked for one" do
    get "/dev_login", params: { role: "caregiver" }

    expect(signed_in_role).to eq("caregiver")
  end

  it "signs in an actual care receiver when asked for one" do
    get "/dev_login", params: { role: "senior" }

    expect(signed_in_role).to eq("care receiver")
  end

  it "ignores a role that is not a role" do
    get "/dev_login", params: { role: "administrator; DROP TABLE users" }

    # Falls through to the email path rather than blowing up or inventing one.
    expect(response).to have_http_status(:found)
    expect(User.where(role: nil).count).to eq(0)
  end

  # The fallback used to be a bare create!, so a database that already had
  # dev-caregiver@example.com under some other role hit the unique email index
  # and the button raised instead of signing anybody in.
  it "still works when its own fixture address is held by the wrong role" do
    User.where(role: :caregiver).destroy_all
    create(:user, :senior, name: "Squatter", email: "dev-caregiver@example.com")

    expect { get "/dev_login", params: { role: "caregiver" } }.not_to raise_error
    expect(signed_in_role).to eq("caregiver")
  end

  # name is validated on update, so an existing dev account with a blank one —
  # the normal state after dev_login has redirected to /profile once — made
  # every later press of the button raise on save!.
  it "survives a second press when its account has no name yet" do
    # Reached only when no caregiver exists at all and the fixture address is
    # held by some other role: with a caregiver present the lookup returns it
    # and never saves. name is not validated on create, so a blank one persists.
    User.where(role: :caregiver).destroy_all
    User.create!(email: "dev-caregiver@example.com", role: :senior, tz: "America/New_York", name: "")

    expect { get "/dev_login", params: { role: "caregiver" } }.not_to raise_error
    expect(signed_in_role).to eq("caregiver")
  end

  it "offers the buttons by role, not by address" do
    get "/login"
    doc = Nokogiri::HTML(response.body)
    links = doc.css("a").select { |a| a.text.include?("Quick Login") }

    expect(links.map { |a| a["href"] }).to all(match(/role=/))
    expect(links.map { |a| a["href"] }).not_to include(match(/email=/))
  end

  it "no longer calls anybody a senior on the sign-in page" do
    get "/login"

    expect(Nokogiri::HTML(response.body).text).to include("Quick Login as Care Receiver")
  end
end
