# frozen_string_literal: true

require "rails_helper"

# Removing a caregiver entirely was already offered on the care receiver's own
# dashboard. Limiting what one can do — the smaller version of the same decision
# — was not, so the only way to hold a view caregiver was a console.
#
# It sits with the care receiver rather than an admin for the same reason
# everything else here does: only they can agree to phone calls, only they can
# generate a pairing token, and a family sorting out who does what should not
# have to email the developer.
RSpec.describe "A care receiver setting what a caregiver may do", type: :request do
  let(:senior) { create(:user, :senior, name: "Nora") }
  let(:caregiver) { create(:user, :caregiver, name: "Sam") }
  let!(:link) { CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  it "can limit a caregiver to looking" do
    sign_in(senior)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "view" }

    expect(link.reload.permission).to eq("view")
  end

  it "can give the ability back" do
    link.update!(permission: :view)
    sign_in(senior)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "manage" }

    expect(link.reload.permission).to eq("manage")
  end

  # Scoped to senior_links, so the only links reachable are ones where the
  # current user is the person being cared for.
  it "cannot be done by the caregiver to themselves" do
    sign_in(caregiver)
    link.update!(permission: :view)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "manage" }

    expect(link.reload.permission).to eq("view")
  end

  it "cannot be done by an unrelated care receiver" do
    other = create(:user, :senior, name: "Pat")
    sign_in(other)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "view" }

    expect(link.reload.permission).to eq("manage")
  end

  it "refuses a permission that does not exist" do
    sign_in(senior)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "admin" }

    expect(link.reload.permission).to eq("manage")
  end

  # Dropping to view does not revoke consent or wipe the number. The calls were
  # agreed to by the care receiver, and ending them because their helper's
  # permission changed would punish the wrong person.
  it "leaves phone reminders already agreed alone" do
    senior.update!(phone: "+15551234567", phone_verified_at: Time.current,
                   call_consent_at: Time.current, call_reminders_enabled: true)
    sign_in(senior)

    patch "/dashboard/caregivers/#{link.id}/permission", params: { permission: "view" }

    expect(senior.reload.callable_by_phone?).to be true
    expect(senior.phone).to eq("+15551234567")
  end

  # The layout loads Tailwind and nothing else, so data-turbo-confirm and
  # data-confirm are both inert here — which is why Remove Access had been
  # deleting a caregiver without asking. A plain onclick is what this page can
  # actually run.
  it "asks before changing anything, with a confirm the page can run" do
    sign_in(senior)
    get "/dashboard"

    buttons = Nokogiri::HTML(response.body).css("input[type=submit], button")
    confirms = buttons.filter_map { |b| b["onclick"] }.grep(/confirm\(/)

    expect(confirms.length).to be >= 2
    expect(response.body).not_to include("turbo-confirm")
  end

  it "names the caregiver rather than emailing at them" do
    sign_in(senior)
    get "/dashboard"

    onclicks = Nokogiri::HTML(response.body).css("input[type=submit], button").filter_map { |b| b["onclick"] }.join(" ")

    expect(onclicks).to include(caregiver.friendly_name)
    expect(onclicks).not_to include(caregiver.email)
  end

  it "shows the choice on the dashboard, beside removing them" do
    sign_in(senior)
    get "/dashboard"
    text = Nokogiri::HTML(response.body).text.gsub(/\s+/, " ")

    expect(text).to include("Can make changes")
    expect(text).to include("Limit to looking")
    expect(text).to include("Remove Access")
  end
end
