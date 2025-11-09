FactoryBot.define do
  factory :scheduling_integration do
    association :user
    association :senior, factory: :user
    
    provider { :acuity }
    status { :active }
    provider_user_id { "12345" }
    api_key { "test_api_key_#{SecureRandom.hex(8)}" }
    sync_enabled { true }
    settings { {} }

    trait :acuity do
      provider { :acuity }
      api_key { "acuity_key_#{SecureRandom.hex(8)}" }
    end

    trait :calendly do
      provider { :calendly }
      api_key { nil }
      access_token { "calendly_token_#{SecureRandom.hex(8)}" }
    end

    trait :inactive do
      status { :inactive }
    end

    trait :error do
      status { :error }
      settings { { last_error: "Test error", last_error_at: Time.current } }
    end

    trait :synced do
      last_synced_at { 1.hour.ago }
    end
  end
end
