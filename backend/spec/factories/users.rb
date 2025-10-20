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
  end
end
