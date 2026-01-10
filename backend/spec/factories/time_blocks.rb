FactoryBot.define do
  factory :time_block do
    user { nil }
    start_time { "2026-01-09 18:43:19" }
    end_time { "2026-01-09 18:43:19" }
    reason { "MyString" }
    recurring { false }
    recurrence_pattern { "MyString" }
    active { false }
  end
end
