FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    role { :caregiver }
    tz { "America/New_York" }

    trait :senior do
      role { :senior }
    end

    trait :caregiver do
      role { :caregiver }
    end

    trait :admin do
      role { :admin }
    end

    # Somebody Remindly may telephone. Compound on purpose: a number, a recorded
    # agreement from the person holding it, and no opt-out since. Setting
    # call_reminders_enabled alone describes a state the application can no
    # longer reach, because only a completed verification call writes it.
    trait :takes_calls do
      phone { "+15551234567" }
      phone_verified_at { Time.current }
      call_consent_at { Time.current }
      call_reminders_enabled { true }
    end
  end
end
