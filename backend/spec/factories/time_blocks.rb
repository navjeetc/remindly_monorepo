FactoryBot.define do
  factory :time_block do
    association :user
    start_time { Time.current }
    end_time { 2.hours.from_now }
    reason { "Unavailable" }
    recurring { false }
    recurrence_pattern { nil }
    active { true }
  end
end
