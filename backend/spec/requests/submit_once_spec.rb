# frozen_string_literal: true

require "rails_helper"

# On 2026-10-30 one tap on "Set them up" from an Android phone created two care
# receivers called John, 50ms apart. The dashboard loads no Turbo or rails-ujs,
# so nothing stopped the second POST. shared/_submit_once does now, from the
# dashboard layout. Its logic is plain browser script with no JS test runner
# here, so this checks the part that can silently go missing: that every
# dashboard page, and the form that double-posted, carries it.
RSpec.describe "One submit per press on dashboard forms", type: :request do
  let(:caregiver) { create(:user, :caregiver) }

  def sign_in(user)
    post "/magic/verify", params: { token: user.signed_id(purpose: :magic_login, expires_in: 30.minutes) }
  end

  def guard_present? = response.body.include?('form.dataset.submitting === "true"')

  before { sign_in(caregiver) }

  it "is on the add-someone page that posted twice" do
    get "/dashboard/care_receiver/new"

    expect(response).to have_http_status(:ok)
    expect(guard_present?).to be(true)
  end

  it "is on the caregiver's dashboard" do
    get "/dashboard"

    expect(guard_present?).to be(true)
  end

  it "is in the page only once" do
    get "/dashboard"

    expect(response.body.scan('document.addEventListener("submit"').size).to eq(1)
  end
end
