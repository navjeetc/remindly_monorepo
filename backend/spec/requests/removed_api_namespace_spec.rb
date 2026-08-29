require "rails_helper"

# The /api namespace was removed. It existed from the client-server era, before
# the voice client was folded into the Rails UI (see retired_client_spec for the
# other half of that migration), and outlived the client it was built for.
#
# It also never ran. All three controllers opened with
# `before_action :authenticate_user!`, which is defined nowhere —
# ApplicationController defines `authenticate!` — so every action raised
# NoMethodError before reaching any code. Nothing called it, nothing tested it,
# and production logged no requests to it in ten months, which is why a typo
# fatal to every request in the namespace went unnoticed that long.
#
# These specs exist so it stays gone: a dead endpoint that looks live is where
# somebody reasonably adds their next task endpoint, and finds it does nothing.
RSpec.describe "the removed /api namespace", type: :request do
  # 404 rather than a raise: request specs run with exceptions rendered, which
  # is what a real client would receive too.
  it "no longer routes tasks" do
    get "/api/tasks"

    expect(response).to have_http_status(:not_found)
  end

  it "no longer routes task comments" do
    get "/api/tasks/1/comments"

    expect(response).to have_http_status(:not_found)
  end

  it "no longer routes availability" do
    get "/api/availability"

    expect(response).to have_http_status(:not_found)
  end

  # The web surfaces that replaced it are the ones under test elsewhere; this is
  # only here to show the removal did not take a live path with it.
  it "left the web task list working" do
    caregiver = create(:user, :caregiver, name: "Sam")
    senior = create(:user, :senior, name: "Nora")
    CaregiverLink.create!(senior: senior, caregiver: caregiver, permission: :manage)
    post "/magic/verify", params: { token: caregiver.signed_id(purpose: :magic_login, expires_in: 30.minutes) }

    get "/seniors/#{senior.id}/tasks"

    expect(response).to have_http_status(:ok)
  end
end
