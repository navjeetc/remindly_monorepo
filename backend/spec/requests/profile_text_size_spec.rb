require "rails_helper"

# The setting exists for someone who cannot read the page it lives on, so the
# two things worth guarding are that the form comes back showing what is stored
# — otherwise a senior "fixes" the size, returns, sees Normal selected, and
# picks it again — and that the choice actually reaches the layout, which is the
# only place it does any work.
RSpec.describe "Profile text size", type: :request do
  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def doc = Nokogiri::HTML(response.body)

  let(:user) { create(:user, :senior, name: "Ada") }

  it "defaults to normal, which leaves the root font size alone" do
    sign_in(user)
    get "/profile"

    expect(user.text_size).to eq("normal")
    expect(doc.at_css("html")[:style]).to eq("font-size: 100%")
  end

  it "stores the chosen size" do
    sign_in(user)

    patch "/profile", params: { user: { name: "Ada", tz: user.tz, text_size: "larger" } }

    expect(user.reload.text_size).to eq("larger")
  end

  it "scales the root font size once a larger size is stored" do
    user.update!(text_size: "large")
    sign_in(user)
    get "/dashboard"

    expect(doc.at_css("html")[:style]).to eq("font-size: 115%")
  end

  it "offers every size the layout knows how to draw" do
    sign_in(user)
    get "/profile"

    offered = doc.css("input[name='user[text_size]']").map { |input| input[:value] }

    expect(offered).to eq(User::TEXT_SCALES.keys)
  end

  it "scales to the largest size, which exists for the people who need it most" do
    user.update!(text_size: "largest")
    sign_in(user)
    get "/dashboard"

    expect(doc.at_css("html")[:style]).to eq("font-size: 150%")
  end

  it "preselects the stored size, so the form does not read as Normal" do
    user.update!(text_size: "larger")
    sign_in(user)
    get "/profile"

    checked = doc.css("input[name='user[text_size]'][checked]")

    expect(checked.map { |input| input[:value] }).to eq([ "larger" ])
  end

  # Rails raises ArgumentError when an unknown value is assigned to an enum, and
  # this attribute arrives straight from a form post, so without `validate: true`
  # on the enum a hand-crafted "giant" took down the profile update with a 500.
  it "refuses a size it cannot draw, without falling over" do
    user.update!(text_size: "large")
    sign_in(user)

    expect {
      patch "/profile", params: { user: { name: "Ada", tz: user.tz, text_size: "giant" } }
    }.not_to change { user.reload.text_size }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "leaves the size alone when the form is submitted without it" do
    user.update!(text_size: "large")
    sign_in(user)

    expect {
      patch "/profile", params: { user: { name: "Ada Lovelace", tz: user.tz } }
    }.not_to change { user.reload.text_size }
  end
end
