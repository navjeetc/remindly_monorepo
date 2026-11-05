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

  # RecordInvalid is rescued by a handler method that rescue_from names as a
  # symbol. Renaming the :unprocessable_entity status to :unprocessable_content
  # renamed that reference too, and nothing caught the missing method until
  # this example existed.
  it "answers an invalid reminder with a 422 and the validation messages" do
    user = User.create!(email: "senior@example.com", tz: "America/New_York")
    jwt  = JWT.encode({ uid: user.id, exp: 1.hour.from_now.to_i }, ENV.fetch("JWT_SECRET", "dev_secret_change_me"), "HS256")
    post "/reminders",
      params: { title: "", rrule: "FREQ=DAILY;BYHOUR=9;BYMINUTE=0", tz: user.tz },
      headers: { "Authorization" => "Bearer #{jwt}" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("error" => "Validation failed")
    expect(response.parsed_body["details"]).to include("Title can't be blank")
  end
end
