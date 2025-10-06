require 'rails_helper'

RSpec.describe "Reminders", type: :request do
  it "creates reminder and expands occurrences" do
    user = User.create!(email: "senior@example.com", tz: "America/New_York")
    jwt  = JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i }, ENV.fetch("JWT_SECRET", "dev_secret_change_me"), "HS256")
    post "/reminders",
      params: { title: "Pill", rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0", tz: user.tz },
      headers: { "Authorization" => "Bearer #{jwt}" }
    expect(response).to have_http_status(:created)
  end
end
