FactoryBot.define do
  factory :caregiver_availability do
    association :caregiver, factory: :user, role: :caregiver
    
    date { Date.current }
    start_time { Time.parse('09:00') }
    end_time { Time.parse('17:00') }
    notes { "Available all day" }

    trait :morning_only do
      start_time { Time.parse('09:00') }
      end_time { Time.parse('12:00') }
      notes { "Morning availability only" }
    end

    trait :afternoon_only do
      start_time { Time.parse('13:00') }
      end_time { Time.parse('17:00') }
      notes { "Afternoon availability only" }
    end

    trait :future do
      date { 1.week.from_now }
    end
  end
end
